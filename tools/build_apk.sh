#!/bin/sh
# 命令行构建（不使用 Gradle）：aapt 编译资源 + kotlinc 编译 + D8 生成 dex + apksigner 签名
#
# 依赖（TOOLCHAIN 目录，默认 /workspace/toolchain）：
#   sdk33/android-13/android.jar     Android SDK platform 33（Debian 自带的 aapt 读不了 API34+ 的新资源表）
#   r8.jar                           com.android.tools:r8（内含 D8）
#   libxposed-api-102.jar            io.github.libxposed:api:102 里的 classes.jar（新版 API）
#   annotation-1.9.1.jar             androidx.annotation（新版 API 编译期依赖）
#   kotlin-compiler-embeddable-2.1.21.jar 及依赖 / kotlin-stdlib-2.1.21.jar
# 系统包：default-jdk aapt apksigner zipalign zip unzip

set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TC=${TOOLCHAIN:-/workspace/toolchain}
SRC="$ROOT/app/src/main"
OUT="$ROOT/build-ondevice"
VERSION_NAME=${VERSION_NAME:-1.32.3}
VERSION_CODE=${VERSION_CODE:-173}


# SHRINK=1（默认）：用 R8 收缩 dex（classes.dex 从 2.2MB → 143KB，见 tools/keep.pro）
# SHRINK=0：退回旧的 D8 全量 dex（排查“装了新版功能没变化/闪退”时的对照用）
SHRINK=${SHRINK:-1}

# 分支包参数（默认就是常规包）。用环境变量覆盖即可产出能与常规包共存的变体，例如：
#   APP_ID=com.eta.sideindex.flyme ICON=ic_side_index_flyme OUT_NAME=SideIndexFlyme sh tools/build_apk.sh
APP_ID=${APP_ID:-com.eta.sideindexx}
ICON=${ICON:-ic_side_index}
OUT_NAME=${OUT_NAME:-SideIndexX}

ANDROID_JAR="$TC/sdk33/android-13/android.jar"
# libxposed 新版 API（io.github.libxposed:api:102）与它编译期需要的 androidx 注解
# ⚠️ 1.32.0 起源码里**不允许**再出现 de.robv.android.xposed.*（旧 API），所以不再挂 xposed-api-82.jar
LXPOSED_JAR="$TC/libxposed-api-102.jar"
ANNOTATION_JAR="$TC/annotation-1.9.1.jar"
R8_JAR="$TC/r8.jar"
STDLIB_JAR="$TC/kotlin-stdlib-2.1.21.jar"
KOTLIN_CP="$TC/kotlin-compiler-embeddable-2.1.21.jar:$STDLIB_JAR:$TC/kotlin-script-runtime-2.1.21.jar:$TC/kotlin-reflect-2.1.21.jar:$TC/kotlin-daemon-embeddable-2.1.21.jar:$TC/trove4j-1.0.20200330.jar:$TC/annotations-13.0.jar:$TC/kotlinx-coroutines-core-jvm-1.9.0.jar"

for f in "$ANDROID_JAR" "$LXPOSED_JAR" "$ANNOTATION_JAR" "$R8_JAR" "$STDLIB_JAR"; do
    [ -f "$f" ] || { echo "缺少 $f"; exit 1; }
done
for c in java javac jar aapt apksigner zipalign zip unzip keytool; do
    command -v "$c" >/dev/null 2>&1 || { echo "缺少命令 $c"; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

echo "==> 源清单包名：$APP_ID 图标：$ICON"

# 分支包与常规包共存的前提：包名、ContentProvider authority、LSPosed 入口类都要换成新的，
# 否则两个包同 authority 会 INSTALL_FAILED_CONFLICTING_PROVIDER，LSPosed 也会认成同一个模块
BRANCH_MARK="$ROOT/.branch-id"
if [ "$APP_ID" != "com.eta.sideindexx" ]; then
    if [ "$(cat "$BRANCH_MARK" 2>/dev/null)" = "$APP_ID" ]; then
        echo "==> 源码已是 $APP_ID，跳过包名改写"
    else
        echo "==> 派生分支包：$APP_ID（改写包名 / provider authority / xposed 入口）"
        grep -rl 'com\.eta\.sideindex' "$SRC" 2>/dev/null | while read -r f; do
            sed -i "s/com\.eta\.sideindex/$APP_ID/g" "$f"
        done
        echo "$APP_ID" > "$BRANCH_MARK"
    fi
fi
if [ "$ICON" != "ic_side_index" ]; then
    echo "==> 分支包图标：@drawable/$ICON"
    sed -i "s|@drawable/ic_side_index|@drawable/$ICON|g" "$SRC/AndroidManifest.xml"
fi

echo "==> 生成带 package 属性的清单（aapt v1 需要）"
sed "s|<manifest |<manifest package=\"$APP_ID\" |" "$SRC/AndroidManifest.xml" > "$OUT/AndroidManifest.xml"

echo "==> 编译资源 + 生成 R.java"
aapt package -f -m -J "$OUT/gen" -M "$OUT/AndroidManifest.xml" -S "$SRC/res" -A "$SRC/assets" \
    -I "$ANDROID_JAR" --min-sdk-version 31 --target-sdk-version 36 \
    --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" -F "$OUT/app-res.apk"

echo "==> 编译 R.java"
javac -nowarn -Xlint:-options --release 17 -cp "$ANDROID_JAR:$STDLIB_JAR" -d "$OUT/classes" \
    $(find "$OUT/gen" -name '*.java')

echo "==> 编译 Kotlin"
java -cp "$KOTLIN_CP" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
    -no-stdlib -jvm-target 17 -nowarn \
    -classpath "$ANDROID_JAR:$STDLIB_JAR:$LXPOSED_JAR:$ANNOTATION_JAR:$OUT/classes" \
    -d "$OUT/classes" "$SRC/java"

echo "==> 生成 classes.dex（合并 kotlin-stdlib，SHRINK=$SHRINK）"
(cd "$OUT/classes" && jar cf "$OUT/code.jar" .)
if [ "$SHRINK" = "1" ]; then
    # R8：收缩（删掉用不到的 kotlin 标准库与自家死代码）+ 优化。
    # 入口与框架回调的 keep 规则在 tools/keep.pro，删规则前先读那里的注释。
    java -Xmx1500m -cp "$R8_JAR" com.android.tools.r8.R8 --release --min-api 31 \
        --lib "$ANDROID_JAR" --lib "$LXPOSED_JAR" --lib "$ANNOTATION_JAR" \
        --pg-conf "$ROOT/tools/keep.pro" \
        --output "$OUT/dex" "$OUT/code.jar" "$STDLIB_JAR"
else
    java -Xmx1500m -cp "$R8_JAR" com.android.tools.r8.D8 --release --min-api 31 \
        --lib "$ANDROID_JAR" --output "$OUT/dex" "$OUT/code.jar" "$STDLIB_JAR"
fi
ls -l "$OUT/dex/classes.dex"

echo "==> 打包"
cp "$OUT/app-res.apk" "$OUT/app-unsigned.apk"
(cd "$OUT/dex" && zip -q -X "$OUT/app-unsigned.apk" classes.dex)

# libxposed 新版 API 的模块描述符必须落在 APK 根的 META-INF/xposed/ 下，
# aapt 只打 res/assets，所以这里手工塞进去（Gradle 构建时对应 src/main/resources/）
if [ -d "$ROOT/xposed/META-INF/xposed" ]; then
    echo "==> 注入 libxposed 描述符"
    (cd "$ROOT/xposed" && zip -q -X "$OUT/app-unsigned.apk" \
        META-INF/xposed/module.prop META-INF/xposed/java_init.list META-INF/xposed/scope.list)
    unzip -l "$OUT/app-unsigned.apk" | grep 'META-INF/xposed' || true
fi
zipalign -f -p 4 "$OUT/app-unsigned.apk" "$OUT/app-aligned.apk"

KS="$ROOT/release.keystore"
if [ ! -f "$KS" ]; then
    keytool -genkeypair -keystore "$KS" -alias sideindex -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass sideindexx -keypass sideindexx -dname "CN=Eta SideIndex, O=Eta, C=CN"
fi

APK="$ROOT/$OUT_NAME-$VERSION_NAME.apk"
apksigner sign --ks "$KS" --ks-pass pass:sideindexx --key-pass pass:sideindexx \
    --out "$APK" "$OUT/app-aligned.apk"
apksigner verify --print-certs "$APK" | head -4
echo "构建完成：$APK"
