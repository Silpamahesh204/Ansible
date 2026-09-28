Java 17 installation - transcription from IMG_1470.mp4 and CameraRecording-9A2E5FFA-61CD-4CEB-8152-BAFD8F2C34DC.mp4

The recording shows a Red Hat Enterprise Linux 8 package manager transaction
for OpenJDK 17. The companion recording shows the install command:
sudo yum install java-17-openjdk

Transaction Summary
-------------------
Installing weak dependencies: gtk3, libthai
Enabling module streams: javapackages-tools 201801
Install 49 Packages
Total download size: 69 M
Installed size: 255 M
Is this ok [y/N]: y
Downloading Packages

Readable downloaded package names (some versions are blurred):
  javapackages-filesystem
  at-spi2-atk
  hicolor-icon-theme
  lcms2
  xorg-x11-fonts-Type1
  at-spi2-core
  graphite2
  cups-libs
  jbigkit-libs
  libXcursor
  libXtst
  ttmkfdir
  libXinerama
  libXdamage
  colord-libs
  libXfixes
  rest
  atk
  libXcomposite
  libfontenc
  libXi
  libXft
  libXrandr
  libdatrie
  dconf
  copy-jdk-configs
  libjpeg-turbo
  lua
  pango
  xorg-x11-font-utils
  libepoxy
  jasper-libs
  fribidi
  adwaita-cursor-theme
  gtk-update-icon-cache
  libwayland-client
  libwayland-cursor
  gtk3
  libwayland-egl
  tzdata-java
  alsa-lib
  harfbuzz
  gdk-pixbuf2-modules
  java-17-openjdk (17.0.12.0.7-2.el8, x86_64)
  libtiff
  adwaita-icon-theme
  java-17-openjdk-headless (17.0.12.0.7-2.el8, x86_64)

Total: 29 MB/s | 69 MB | 00:02
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
[The 49 packages are installed and verified.]
Installed products updated.
Installed: [the same Java 17 packages and dependencies listed above]
Complete!

Transcription note: The video is a moving, slightly blurry recording of a
long package manager log. Download rates, individual transaction counters,
and repetitive install/verify lines are abbreviated. No `java -version` verification is visible in either clip. The install
command appears in the companion recording.
