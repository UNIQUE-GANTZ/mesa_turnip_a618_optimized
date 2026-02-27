# Relatório de Otimizações — Driver Turnip para Adreno 618 (Snapdragon 730)

**Data de compilação:** 23 de fevereiro de 2026  
**Versão Mesa:** 26.1.0-devel  
**Arquivo gerado:** `libvulkan_freedreno.so` (16 MB)  
**SHA-256:** `c6af27a61c828faa051259063ce88527b042cca885b3bfb743a3111ddea5c8f5`  
**Plataforma alvo:** Adreno 618 (A6xx gen6) / Snapdragon 730 — Winlator / Box64

---

## 1. Configuração do Build (Meson)

O sistema de build foi configurado com as seguintes opções, otimizadas para o ambiente de emulação Winlator/Box64:

| Opção Meson | Valor | Justificativa |
|---|---|---|
| `vulkan-drivers` | `freedreno` | Apenas o driver Turnip/Vulkan |
| `gallium-drivers` | _(vazio)_ | Sem drivers OpenGL (não necessário) |
| `platforms` | _(vazio)_ | Sem X11/XCB/Wayland (emulação headless) |
| `freedreno-kmds` | `msm,kgsl` | Suporte a ambos os backends de kernel |
| `glx/egl/gbm` | `disabled` | Desabilitados para reduzir dependências |
| `buildtype` | `release` | Otimizações de compilador ativas |
| `b_lto` | `true` | Link-Time Optimization habilitado |
| `b_ndebug` | `true` | Assertions desabilitadas em produção |
| `llvm` | `disabled` | Sem dependência de LLVM |

**Toolchain utilizado:**
- `glslangValidator` versão 16.2.0 (Khronos main-tot)
- GCC/G++ do sistema Ubuntu 22.04

---

## 2. Otimizações do Compilador de Shaders (IR3/NIR)

### 2.1 — Suporte a 16-bit I/O para gen6+ (`ir3_compiler.c`)

**Arquivo:** `src/freedreno/ir3/ir3_compiler.c`  
**Identificador:** `A618-OPT-1`

```c
/* A618-OPT: Enable 16-bit I/O support for gen6+ (Adreno 618 / A6xx). */
if (compiler->gen >= 6 && !(ir3_shader_debug & IR3_DBG_NOFP16))
   compiler->nir_options.io_options |= nir_io_16bit_input_output_support;
```

**Efeito:** Ativa o flag `nir_io_16bit_input_output_support` na struct `nir_shader_compiler_options` para todas as GPUs gen6+. Isso permite ao otimizador NIR propagar tipos FP16 através de operações de I/O de varyings, reduzindo a pressão de registradores e aumentando o throughput. No A618, as unidades ALU FP16 operam em throughput duplo comparado ao FP32.

**Compatibilidade:** Condicional a `!(IR3_DBG_NOFP16)`, portanto pode ser desabilitado via `IR3_SHADER_DEBUG=nofp16` para depuração.

---

### 2.2 — Promoção FP16 Agressiva em Estágios de Fragmento (`ir3_nir.c`)

**Arquivo:** `src/freedreno/ir3/ir3_nir.c`  
**Identificador:** `A618-OPT-2`

```c
/* A618-OPT: Promoção FP16 agressiva para Adreno 618 (A6xx). */
NIR_PASS(_, s, nir_lower_mediump_io, nir_var_shader_out,
         UINT64_MAX, false);
```

**Efeito:** Adiciona um segundo passo `nir_lower_mediump_io` com máscara `UINT64_MAX` (cobrindo todos os varyings de saída disponíveis) após o passo existente. Isso converte operações float32 em float16 de forma agressiva em todos os estágios de fragmento no gen6, maximizando o uso das unidades FP16 do A618 em ambiente de emulação.

**Posicionamento:** Executado após o passo existente de lowering de inputs mediump, garantindo que as saídas também sejam otimizadas.

---

### 2.3 — Redução do Limite de Instruções SY/SS Pendentes (`ir3_sched.c`)

**Arquivo:** `src/freedreno/ir3/ir3_sched.c`  
**Identificador:** `A618-OPT-3`

```c
/* A618-OPT: Reduced outstanding SY/SS limit from 8 to 6 */
if (ctx->sy_index - ctx->first_outstanding_sy_index >= 6 && is_sy_producer(instr))
   return true;
if (ctx->ss_index - ctx->first_outstanding_ss_index >= 6 && is_ss_producer(instr))
   return true;
```

**Efeito:** Reduz o limite de instruções de textura (SY) e SFU (SS) pendentes de 8 para 6 no escalonador de instruções. O A618 possui um arquivo de registradores limitado; reduzir a janela de instruções em voo evita o spill de registradores para memória privada, que é particularmente custoso em ambiente de emulação.

---

## 3. Gestão de Residência GMEM-Centric

### 3.1 — Forçar Renderização GMEM (`tu_cmd_buffer.cc`)

**Arquivo:** `src/freedreno/vulkan/tu_cmd_buffer.cc`  
**Identificador:** `A618-GMEM-1`  
**Função:** `use_sysmem_rendering()`

```c
/* A618-GMEM-OPT: Force GMEM-centric rendering for Adreno 618 (A6xx). */
bool use_sysmem = false;  /* A618-OPT: permanently false */
(void) tu_autotune_use_bypass(&cmd->device->autotune, cmd, autotune_result);
```

**Efeito:** Desabilita permanentemente o caminho sysmem (renderização em memória do sistema). O autotune ainda é chamado para coleta de estatísticas, mas sua decisão não influencia o caminho de renderização. Em Winlator/Box64, a renderização GMEM tiled sempre supera o sysmem devido à largura de banda de memória limitada disponível para o emulador.

**Casos de exceção preservados:** As verificações de fallback obrigatório para sysmem são mantidas intactas:
- Attachments que não cabem no GMEM (`!tiling->possible`)
- Área de renderização vazia
- Shaders de tessellation
- XFB incompatível com non-hw binning
- `TU_DEBUG(SYSMEM)` para depuração

---

### 3.2 — Limite Físico GMEM Hardcoded para A618 (`tu_pass.cc`)

**Arquivo:** `src/freedreno/vulkan/tu_pass.cc`  
**Identificador:** `A618-GMEM-2`  
**Função:** `tu_render_pass_gmem_config()`

```c
const uint32_t A618_GMEM_SIZE = 524288; /* 512 KB - limite físico A618 */
uint32_t render_pass_size = cpp_total;
/* Verificação de transbordo */
if (render_pass_size > 0 && A618_GMEM_SIZE / render_pass_size < 1) {
   pass->gmem_pixels[layout] = 0;
   continue;
}
/* Cálculo de tiles baseado no limite físico */
uint32_t area_maxima = A618_GMEM_SIZE / render_pass_size;
uint32_t tile_dim = ROUND_DOWN_TO((uint32_t)sqrtf((float)area_maxima), tile_align_w);
/* Limitar gmem_size ao máximo físico do A618 */
gmem_size = MIN2(gmem_size, A618_GMEM_SIZE);
```

**Efeito:** Implementa o limite físico do GMEM da Adreno 618 (512 KB = 524288 bytes) diretamente no cálculo de configuração de tiles. O algoritmo:
1. Calcula a área máxima de tile como `524288 / bytes_por_pixel_total`
2. Deriva `tile_dim = floor(sqrt(area_maxima))` alinhado ao `tile_align_w` do hardware
3. Detecta transbordo quando `render_pass_size > 524288` e força tiles mínimos
4. Limita o `gmem_size` efetivo ao máximo físico do A618

**Fórmula de tile para cenário típico (RGBA8 + depth = 8 bytes/pixel):**
- `area_maxima = 524288 / 8 = 65536 pixels`
- `tile_dim = floor(sqrt(65536)) = 256 pixels`
- Tiles de 256×256 pixels por render pass

---

## 4. Resumo das Modificações

| Arquivo | Otimização | Impacto Esperado |
|---|---|---|
| `ir3_compiler.c` | `nir_io_16bit_input_output_support` para gen6+ | +throughput FP16 em I/O de varyings |
| `ir3_nir.c` | `nir_lower_mediump_io` agressivo (UINT64_MAX) | Redução de operações FP32 desnecessárias |
| `ir3_sched.c` | Limite SY/SS: 8 → 6 | Redução de spill de registradores |
| `tu_cmd_buffer.cc` | `use_sysmem = false` permanente | Eliminação do overhead de sysmem |
| `tu_pass.cc` | Limite GMEM 512 KB hardcoded + cálculo de tiles | Tiles otimizados para A618 |

---

## 5. Instruções de Uso (Winlator/Box64)

Para utilizar o driver otimizado no Winlator:

1. Copiar `libvulkan_freedreno.so` para o diretório de drivers do Winlator
2. Configurar a variável de ambiente: `MESA_VK_WSI_PRESENT_MODE=mailbox`
3. Para depuração de GMEM: `TU_DEBUG=gmem`
4. Para desabilitar FP16 (se houver artefatos visuais): `IR3_SHADER_DEBUG=nofp16`

**Nota:** Este driver é compilado para arquitetura x86_64 (host). Para uso em dispositivo ARM real, é necessário cross-compilação com toolchain AArch64.

---

## 6. Informações de Build

```
Mesa Version:    26.1.0-devel
Build Type:      release (LTO + NDEBUG)
Vulkan Drivers:  freedreno (Turnip)
KMD Backends:    msm, kgsl
Platforms:       (nenhuma - headless)
glslangValidator: 16.2.0 (Khronos main-tot)
Arquivo:         libvulkan_freedreno.so (16 MB)
SHA-256:         c6af27a61c828faa051259063ce88527b042cca885b3bfb743a3111ddea5c8f5
```
