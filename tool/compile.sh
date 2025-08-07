ARCH=$(uname -m)
echo "AAAAAA Inside $ARCH container AAAAAA"
ldd --version || true
dpkg -s libc6 | grep Version || true

echo "Installing build tools (g++, make, cmake) inside $ARCH container..."
apt-get update && apt-get install -y build-essential

cd lib-src
make -j$(getconf _NPROCESSORS_ONLN) libquickjs.so
