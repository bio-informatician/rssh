#!/usr/bin/env python3
"""
Rakhssh SSH Android APK Automated Build & Packaging Pipeline.

Compiles Android XML resources via aapt2, compiles Java sources via javac,
links JSch SSH engine, generates Dalvik Executable bytecode via d8, bundles
web terminal assets into assets/web, aligns via zipalign, and signs the resulting
APK via apksigner with a verified debug keystore.
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
JAVA_DIR = os.path.join(MAIN_SRC, "java", "org", "rssh", "terminal")
WEB_DIR = os.path.join(PROJECT_ROOT, "web")
LIBS_DIR = os.path.join(PROJECT_ROOT, "libs")
JSCH_JAR = os.path.join(LIBS_DIR, "jsch.jar")
MANIFEST_PATH = os.path.join(MAIN_SRC, "AndroidManifest.xml")
BUILD_DIR = os.path.join(PROJECT_ROOT, "build")

# Toolchain paths
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
    print("      Rakhssh SSH Android APK Automated Build Pipeline")
    print("=" * 65)

    # 1. Clean & prepare build directories
    if os.path.exists(BUILD_DIR):
        shutil.rmtree(BUILD_DIR)
    os.makedirs(BUILD_DIR, exist_ok=True)

    assets_dir = os.path.join(BUILD_DIR, "assets", "web")
    os.makedirs(assets_dir, exist_ok=True)
    for fname in ["index.html", "app.js", "style.css", "xterm.js", "xterm.css", "xterm-addon-fit.js"]:
        src = os.path.join(WEB_DIR, fname)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(assets_dir, fname))

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
    unaligned_apk = os.path.join(BUILD_DIR, "rssh-unaligned.apk")
    run_cmd([
        AAPT2, "link",
        "-I", ANDROID_JAR,
        "--manifest", MANIFEST_PATH,
        "--min-sdk-version", "26",
        "--target-sdk-version", "34",
        "--version-code", "2",
        "--version-name", "1.0.1",
        "-A", os.path.join(BUILD_DIR, "assets"),
        "-o", unaligned_apk,
        "--java", gen_dir,
        compiled_res
    ], "Linking APK and generating R.java via aapt2")

    # 4. Compile Java sources via javac
    java_files = [os.path.join(gen_dir, "org", "rssh", "terminal", "R.java")]
    for root, _, files in os.walk(JAVA_DIR):
        for f in files:
            if f.endswith(".java"):
                java_files.append(os.path.join(root, f))

    classpath = f"{ANDROID_JAR}:{JSCH_JAR}"
    javac_cmd = [
        JAVAC,
        "-encoding", "UTF-8",
        "-source", "1.8",
        "-target", "1.8",
        "-cp", classpath,
        "-d", classes_dir
    ] + java_files
    run_cmd(javac_cmd, "Compiling Java sources via javac")

    # Collect compiled class files
    class_files = []
    for root, _, files in os.walk(classes_dir):
        for f in files:
            if f.endswith(".class"):
                class_files.append(os.path.join(root, f))

    # 5. Generate Dalvik Executable (dex) via d8 (including jsch.jar)
    d8_cmd = [
        D8,
        "--lib", ANDROID_JAR,
        "--min-api", "26",
        "--output", dex_dir
    ] + class_files + [JSCH_JAR]
    run_cmd(d8_cmd, "Generating Dalvik Executable bytecode via d8")

    # 6. Add classes.dex to the unaligned APK
    classes_dex = os.path.join(dex_dir, "classes.dex")
    with zipfile.ZipFile(unaligned_apk, "a", compression=zipfile.ZIP_DEFLATED) as apk_zip:
        apk_zip.write(classes_dex, "classes.dex")
        # Check if d8 generated multidex (classes2.dex, etc.)
        classes2_dex = os.path.join(dex_dir, "classes2.dex")
        if os.path.exists(classes2_dex):
            apk_zip.write(classes2_dex, "classes2.dex")

    # 7. 4-byte alignment via zipalign
    aligned_apk = os.path.join(BUILD_DIR, "rssh-aligned.apk")
    run_cmd([ZIPALIGN, "-f", "-p", "4", unaligned_apk, aligned_apk], "Aligning APK package via zipalign")

    # 8. Ensure debug keystore exists
    if not os.path.exists(DEBUG_KEYSTORE):
        os.makedirs(os.path.dirname(DEBUG_KEYSTORE), exist_ok=True)
        run_cmd([
            KEYTOOL, "-genkeypair", "-v",
            "-keystore", DEBUG_KEYSTORE,
            "-storepass", "android",
            "-alias", "androiddebugkey",
            "-keypass", "android",
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "10000",
            "-dname", "CN=Android Debug,O=Android,C=US"
        ], "Generating debug keystore")

    # 9. Sign APK via apksigner
    final_apk = os.path.join(PROJECT_ROOT, "rssh.apk")
    run_cmd([
        APKSIGNER, "sign",
        "--ks", DEBUG_KEYSTORE,
        "--ks-pass", "pass:android",
        "--key-pass", "pass:android",
        "--ks-key-alias", "androiddebugkey",
        "--out", final_apk,
        aligned_apk
    ], "Signing APK via apksigner")

    # 10. Verify signature
    verify_out = run_cmd([APKSIGNER, "verify", "--verbose", final_apk], "Verifying cryptographic signature")
    print(verify_out.strip())

    # 11. Stage deliverables in ~/agent-work
    stage_apk = os.path.expanduser("~/agent-work/rssh.apk")
    stage_versioned = os.path.expanduser("~/agent-work/rssh-v1.0.1.apk")
    shutil.copy2(final_apk, stage_apk)
    shutil.copy2(final_apk, stage_versioned)

    size_kb = os.path.getsize(stage_apk) / 1024
    print("=" * 65)
    print(f" BUILD SUCCESSFUL: {stage_apk} ({size_kb:.1f} KB)")
    print(f" Versioned APK:    {stage_versioned}")
    print("=" * 65)


if __name__ == "__main__":
    build_apk()
