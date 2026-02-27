#!/bin/bash
set -e

# Cores para o terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Iniciando Build do Driver Turnip Otimizado (A618) ===${NC}"

# 1. Instalar dependências necessárias
echo -e "${GREEN}[1/4] Instalando dependências do sistema...${NC}"
sudo apt-get update
sudo apt-get install -y \
    python3-pip python3-setuptools python3-mako python3-yaml \
    libxcb-dri2-0-dev libxcb-dri3-dev libxcb-present-dev \
    libxshmfence-dev libx11-xcb-dev libxrandr-dev libxext-dev \
    libxml2-dev libelf-dev spirv-tools rustc cargo cbindgen ninja-build

# 2. Atualizar Meson
echo -e "${GREEN}[2/4] Atualizando Meson para v1.4.0+...${NC}"
sudo pip3 install --upgrade meson

# 3. Configurar variáveis de ambiente
export GLSLANG="$(pwd)/toolchain/bin/glslangValidator"
chmod +x "$GLSLANG"

# 4. Configurar e Compilar
echo -e "${GREEN}[3/4] Configurando o Meson...${NC}"
rm -rf build_a618
meson setup build_a618 \
    -Dvulkan-drivers=freedreno \
    -Dgallium-drivers="" \
    -Dplatforms="" \
    -Dfreedreno-kmds=msm,kgsl \
    -Dglx=disabled \
    -Degl=disabled \
    -Dgbm=disabled \
    -Dopengl=false \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dllvm=disabled \
    -Dbuildtype=release \
    -Db_lto=false \
    -Db_ndebug=true \
    --prefix="$(pwd)/install"

echo -e "${GREEN}[4/4] Compilando o driver...${NC}"
ninja -C build_a618 src/freedreno/vulkan/libvulkan_freedreno.so

echo -e "${BLUE}=== Build Concluído com Sucesso! ===${NC}"
echo -e "O driver está em: ${GREEN}build_a618/src/freedreno/vulkan/libvulkan_freedreno.so${NC}"
echo -e "O manifesto meta.json está na raiz deste diretório."
