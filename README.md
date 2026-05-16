# MM One UI 7 Theme Mod

A project that extracts the Samsung MM theme APK from CSC firmware and rebuilds it as a modified, re-signed theme package.

---

## Project Layout

| Path | Description |
|---|---|
| `firmware/` | Place the CSC firmware `.tar`, `.tar.md5`, or `.md5` files here |
| `proprietary/` | Output location for APKs extracted by `extract-files.sh` |
| `keys/` | Signing keys (`key.x509.pem`, `key.pk8`). Defaults to the Android Testkey |
| `output/` | Output location for the final APK produced by `thememod.sh` |
| `proprietary-files.txt` | List of firmware-internal paths to extract |
| `extract-files.sh` | Extracts files from firmware images |
| `thememod.sh` | Modifies, zipaligns, and signs the theme APK |

---

## Prerequisites — Firmware Download

1. Download the CSC firmware from the link below:

   <https://samfw.com/firmware/SM-F721N/KOO/F721NKSS6HYGB>

   Filename:
   ```
   CSC_OKT_F721NOKT6HYGB_QB99309021_REV00_user_low_ship_MULTI_CERT.tar.md5.zip
   ```

2. Unzip the downloaded archive. The inner `.tar` or `.tar.md5` file will later be placed into the `firmware/` folder.

---

## Setup

### 1. Install Git and Clone the Repository

```bash
sudo apt install git
git clone -b OneUI7_MM_ZFlip4 https://github.com/fast1ine/SamsungThemeMod.git
cd SamsungThemeMod
```

After cloning, the `firmware/` folder is created. Place the previously extracted `.tar` or `.tar.md5` file into it.

The `keys/` folder ships with the Android Testkey by default and may be replaced with a custom key file if needed.

### 2. Install Dependencies

Firmware extraction tools:

```bash
sudo apt install -y \
    tar lz4 p7zip-full coreutils file findutils
```

APK build and signing tools:

```bash
sudo apt install -y \
    zipalign signapk apksigner unzip zip perl aapt sed grep \
    android-framework-res default-jre-headless \
    libantlr3-runtime-java libcommons-cli-java libcommons-io-java \
    libcommons-lang3-java libcommons-text-java libguava-java \
    libsmali-java libstringtemplate-java libxmlunit-java \
    libxpp3-java libyaml-snake-java
```

### 3. Install Apktool

```bash
wget https://github.com/iBotPeaches/Apktool/releases/download/v2.12.1/apktool_2.12.1.jar -O apktool.jar
wget https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool
chmod +x apktool
sudo mv apktool     /usr/local/bin/
sudo mv apktool.jar /usr/local/bin/
```

---

## Usage

Grant execute permission to the scripts and run them in order:

```bash
chmod +x extract-files.sh thememod.sh

./extract-files.sh   # Extract theme-related files from the CSC firmware
./thememod.sh        # Modify, zipalign, and sign the extracted APK
```

---

## Output

The final APK is produced at:

```text
output/MODed_OneUI7.0_ZFlip4_MM_Edition_v1.0.apk
```
