# Mesa Turnip A618 Optimized Source

Este repositório contém o código-fonte otimizado do driver **Vulkan Turnip** para GPUs **Adreno 618**. O foco principal é a performance e estabilidade em dispositivos móveis.

## 🚀 Como Buildar e Instalar

Para garantir que todas as otimizações e configurações específicas sejam aplicadas corretamente, utilize o script de automação fornecido.

### Passo Único: Executar o Script de Build

Abra o terminal na raiz do repositório e execute:

```bash
chmod +x build_turnip.sh
./build_turnip.sh
```

### O que o script faz:
1.  **Dependências:** Instala automaticamente as bibliotecas de sistema necessárias (via `apt-get`).
2.  **Ferramentas:** Atualiza o `meson` para a versão mais recente e configura o `glslangValidator`.
3.  **Configuração:** Prepara o ambiente de build (`build_a618`) com flags específicas para Adreno 618 (ex: `vulkan-drivers=freedreno`, `buildtype=release`).
4.  **Compilação:** Gera o driver otimizado usando `ninja`.

---

## 📂 Localização dos Arquivos Gerados

Após a conclusão do build, você encontrará os arquivos necessários nos seguintes locais:

- **Driver Vulkan:** `build_a618/src/freedreno/vulkan/libvulkan_freedreno.so`
- **Manifesto:** `meta.json` (localizado na raiz do repositório)

---

## 🛠️ Detalhes Técnicos (Lógica do Build)

O build é configurado com as seguintes definições críticas:
- **Drivers:** Apenas `freedreno` (Vulkan) é habilitado.
- **Plataformas:** Desabilitadas para reduzir o overhead (build focado no driver puro).
- **KMDs:** Suporte para `msm` e `kgsl`.
- **Otimização:** Tipo `release` com `ndebug=true` para máxima performance.

---

## 📄 Licença
Este projeto é baseado no [Mesa 3D Graphics Library](https://mesa3d.org) e segue suas respectivas licenças.
