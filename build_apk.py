#!/usr/bin/env python3
"""
Rakhssh Chat Android APK Automated Build & Packaging Pipeline.

Compiles Android XML resources via aapt2, compiles Java sources via javac,
generates Dalvik Executable bytecode via d8, bundles web assets into assets/web,
aligns via zipalign, and signs the resulting APK via apksigner with
a verified debug keystore.
"""

import os
import sys
import shutil
import subprocess
import zipfile

PROJECT_ROOT = os.path.abspath(os.path.dirname(__file__))
APP_DIR = os.path.join(PROJECT_ROOT, "app")
MAIN_SRC = os.path.join(APP_DIR, "src", "main")
RES_DIR = os.path.join(MAIN_SRC, "res")
JAVA_DIR = os.path.join(MAIN_SRC, "java", "org", "rssh", "chat")
WEB_DIR = os.path.join(PROJECT_ROOT, "web")
MANIFEST_PATH = os.path.join(MAIN_SRC, "AndroidManifest.xml")
BUILD_DIR = os.path.join(PROJECT_ROOT, "build")

# Android SDK and JDK paths
JDK_HOME = os.path.expanduser("~/agent-work/bin/jdk-17")
SDK_HOME = os.path.expanduser("~/agent-work/bin/android-sdk")
ANDROID_JAR = os.path.join(SDK_HOME, "platforms", "android-34", "android.jar")
BUILD_TOOLS = os.path.join(SDK_HOME, "build-tools", "34.0.0")

AAPT2 = os.path.join(BUILD_TOOLS, "aapt2")
D8 = os.path.join(BUILD_TOOLS, "d8")
ZIPALIGN = os.path.join(BUILD_TOOLS, "zipalign")
APKSIGNER = os.path.join(BUILD_TOOLS, "apksigner")
JAVAC = os.path.join(JDK_HOME, "bin", "javac")
KEYTOOL = os.path.join(JDK_HOME, "bin", "keytool")

DEBUG_KEYSTORE = os.path.expanduser("~/agent-work/.android/debug.keystore")


def run_cmd(cmd, step_name):
    print(f"--> {step_name}...")
    env = os.environ.copy()
    env["JAVA_HOME"] = JDK_HOME
    env["PATH"] = f"{os.path.join(JDK_HOME, 'bin')}:{env.get('PATH', '')}"
    env["ANDROID_HOME"] = SDK_HOME

    res = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"ERROR in {step_name} (Exit code {res.returncode}):")
        print(res.stdout)
        print(res.stderr)
        sys.exit(1)
    return res.stdout


def build_apk():
    print("=" * 65)
    print("      Rakhssh Chat Android APK Automated Build Pipeline")
    print("=" * 65)

    # 1. Clean & prepare build directories
    if os.path.exists(BUILD_DIR):
        shutil.rmtree(BUILD_DIR)
    os.makedirs(BUILD_DIR, exist_ok=True)

    assets_dir = os.path.join(BUILD_DIR, "assets", "web")
    os.makedirs(assets_dir, exist_ok=True)
    for fname in ["index.html", "app.js", "style.css"]:
        src = os.path.join(WEB_DIR, fname)
        dst = os.path.join(assets_dir, fname)
        shutil.copy2(src, dst)

    gen_dir = os.path.join(BUILD_DIR, "gen")
    classes_dir = os.path.join(BUILD_DIR, "classes")
    dex_dir = os.path.join(BUILD_DIR, "dex")
    os.makedirs(gen_dir, exist_ok=True)
    os.makedirs(classes_dir, exist_ok=True)
    os.makedirs(dex_dir, exist_ok=True)

    # 2. Compile resources via aapt2
    compiled_res = os.path.join(BUILD_DIR, "compiled_res.zip")
    run_cmd([AAPT2, "compile", "--dir", RES_DIR, "-o", compiled_res], "Compiling resources via aapt2")

    # 3. Link resources and generate base unaligned APK and R.java
    unaligned_apk = os.path.join(BUILD_DIR, "chat-unaligned.apk")
    run_cmd([
        AAPT2, "link",
        "-I", ANDROID_JAR,
        "--manifest", MANIFEST_PATH,
        "-A", os.path.join(BUILD_DIR, "assets"),
        "-o", unaligned_apk,
        "--java", gen_dir,
        compiled_res
    ], "Linking APK and generating R.java via aapt2")

    # 4. Compile Java sources via javac
    java_files = [
        os.path.join(gen_dir, "org", "rssh", "chat", "R.java"),
        os.path.join(JAVA_DIR, "ChatApplication.java"),
        os.path.join(JAVA_DIR, "MainActivity.java")
    ]
    run_cmd([
        JAVAC,
        "-cp", ANDROID_JAR,
        "-d", classes_dir,
        *java_files
    ], "Compiling Java bytecode via javac")

    # 5. Compile bytecode to Dalvik Executable (classes.dex) via d8
    class_files = []
    for root, _, files in os.walk(classes_dir):
        for f in files:
            if f.endswith(".class"):
                class_files.append(os.path.join(root, f))

    run_cmd([
        D8,
        "--lib", ANDROID_JAR,
        "--min-api", "26",
        "--output", dex_dir,
        *class_files
    ], "Compiling Dalvik bytecode via d8")

    # 6. Add classes.dex into unaligned APK
    print("--> Packaging classes.dex into APK archive...")
    with zipfile.ZipFile(unaligned_apk, "a") as zf:
        zf.write(os.path.join(dex_dir, "classes.dex"), "classes.dex")

    # 7. Zipalign APK (4-byte boundary alignment)
    aligned_apk = os.path.join(BUILD_DIR, "chat-aligned.apk")
    run_cmd([ZIPALIGN, "-v", "-p", "4", unaligned_apk, aligned_apk], "Aligning APK via zipalign")

    # 8. Ensure keystore exists
    if not os.path.exists(DEBUG_KEYSTORE):
        os.makedirs(os.path.dirname(DEBUG_KEYSTORE), exist_ok=True)
        run_cmd([
            KEYTOOL, "-genkeypair", "-v",
            "-keystore", DEBUG_KEYSTORE,
            "-alias", "androiddebugkey",
            "-keypass", "pass:android", "-storepass", "pass:android",
            "-dname", "CN=Android Debug,O=Android,C=US",
            "-validity", "10000",
            "-keyalg", "RSA", "-keysize", "2048"
        ], "Generating Android debug keystore")

    # 9. Sign APK via apksigner (v1, v2, v3)
    final_apk = os.path.join(BUILD_DIR, "chat.apk")
    run_cmd([
        APKSIGNER, "sign",
        "--ks", DEBUG_KEYSTORE,
        "--ks-pass", "pass:android",
        "--key-pass", "pass:android",
        "--v1-signing-enabled", "true",
        "--v2-signing-enabled", "true",
        "--v3-signing-enabled", "true",
        "--out", final_apk,
        aligned_apk
    ], "Signing APK via apksigner (v1, v2, v3 schemes)")

    # 10. Verify cryptographic signatures
    sig_out = run_cmd([APKSIGNER, "verify", "--verbose", final_apk], "Verifying APK cryptographic signatures")
    assert "Verifies" in sig_out, "APK verification failed!"

    # 11. Copy to ~/agent-work/chat.apk and versioned ~/agent-work/chat-v1.1.0.apk
    version_name = "1.1.0"
    try:
        import re
        with open(MANIFEST_PATH, "r", encoding="utf-8") as mf:
            m = re.search(r'android:versionName="([^"]+)"', mf.read())
            if m:
                version_name = m.group(1)
    except Exception:
        pass

    staged_apk = os.path.expanduser("~/agent-work/chat.apk")
    versioned_apk = os.path.expanduser(f"~/agent-work/chat-v{version_name}.apk")
    shutil.copy2(final_apk, staged_apk)
    shutil.copy2(final_apk, versioned_apk)

    size_kb = os.path.getsize(staged_apk) / 1024
    print("=" * 65)
    print(f"🎉 SUCCESS! APK built, verified, and staged at:")
    print(f"   {staged_apk} ({size_kb:.1f} KB)")
    print(f"   {versioned_apk} ({size_kb:.1f} KB)")
    print("=" * 65)
    return versioned_apk


if __name__ == "__main__":
    build_apk()
