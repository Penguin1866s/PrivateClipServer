# PrivateClipServer
## Documentación del Proyecto de Fin de Ciclo
### CFGS Administración de Sistemas Informáticos en Red (ASIR) — Módulo de Proyecto

---

> **Nota sobre el código fuente y capturas:** Todo el código del proyecto está escrito íntegramente en inglés. Los fragmentos de código reproducidos en este documento o adjuntados como capturas de pantalla mantienen el idioma original del repositorio.

---

## Índice

1. [Objetivos del proyecto](#1-objetivos-del-proyecto)
2. [Justificación y necesidades del cliente](#2-justificación-y-necesidades-del-cliente)
3. [Solución adoptada](#3-solución-adoptada)
4. [Actividades en que se divide la ejecución](#4-actividades-en-que-se-divide-la-ejecución)
5. [Planificación de la ejecución](#5-planificación-de-la-ejecución)
6. [Seguimiento y control de la ejecución](#6-seguimiento-y-control-de-la-ejecución)
7. [Conclusiones](#7-conclusiones)
8. [Presupuesto](#8-presupuesto)
9. [Bibliografía y repositorio](#9-bibliografía-y-repositorio)

---

## 1. Objetivos del proyecto

### 1.1 Objetivo general

Diseñar, implementar y documentar un servidor privado de intercambio de videoclips que garantice la soberanía total de los datos, opere exclusivamente a través de una VPN propia, automatice el procesado y transcodificación de vídeo, y sea lo suficientemente eficiente para ejecutarse de forma continua en hardware de bajo consumo — concretamente, un mini PC con procesador Intel N150.

### 1.2 Objetivos específicos

**OE-01 — Aislamiento de red mediante VPN propia**
Implementar un servidor VPN WireGuard autocontenido que actúe como único punto de entrada al sistema. Ningún servicio del stack debe ser accesible desde internet sin pasar por el túnel cifrado. La gestión de clientes (peers) debe ser automática y no requerir intervención manual en ficheros de configuración.

**OE-02 — Interfaz web de gestión de ficheros**
Integrar FileBrowser como interfaz web de carga, visualización y descarga de archivos, accesible únicamente desde dentro de la VPN en la dirección `http://10.0.0.1:8080`.

**OE-03 — Pipeline de transcodificación automático**
Cualquier vídeo subido a la carpeta `raw/` debe ser transcodificado automáticamente a un formato universalmente compatible (`H.264 / AAC / yuv420p`) sin intervención del usuario. El fichero original debe conservarse intacto.

**OE-04 — Tolerancia a vídeos corruptos**
El pipeline debe ser capaz de procesar vídeos procedentes de grabadores como Nvidia Instant Replay, que habitualmente contienen corrupción en los primeros fotogramas por corte de GOP a mitad. El sistema debe detectar y localizar el primer punto de decodificación limpio de forma automática.

**OE-05 — Cola de procesado FIFO**
Si se suben varios vídeos simultáneamente, el sistema debe encolarlos y procesarlos en orden de llegada, sin pérdidas y sin bloquear la interfaz web durante el procesado.

**OE-06 — Barra de progreso en tiempo real**
Los usuarios deben poder ver, sin salir de FileBrowser, el progreso del vídeo en procesado (porcentaje, tiempo transcurrido, ETA, velocidad) y la lista de vídeos pendientes en cola.

**OE-07 — Eficiencia de recursos y bajo consumo**
Todo el sistema debe ejecutarse en contenedores Docker ligeros optimizados para minimizar el uso de CPU, RAM y escrituras en disco, con vistas a su despliegue permanente en un mini PC con procesador Intel N150 (~6W TDP).

**OE-08 — Despliegue reproducible con un solo comando**
El proyecto debe poder arrancarse íntegramente con un único comando (`bash main_use.sh`) en cualquier máquina Linux compatible, sin configuración previa.

**OE-09 — Documentación técnica y de uso**
Elaborar un README técnico completo que cubra instalación, uso, arquitectura, referencia de puertos, resolución de incidencias y scripts de cliente para Windows, Linux/macOS y móvil.

---

## 2. Justificación y necesidades del cliente

### 2.1 Contexto del cliente

El cliente tipo de este proyecto es una **pequeña productora audiovisual o equipo de creación de contenido** que genera habitualmente material de vídeo en bruto (gameplay, grabaciones de pantalla, clips de cámara) y necesita compartirlo de forma ágil entre sus miembros — editores, creadores y revisores — independientemente de su ubicación geográfica.

### 2.2 Necesidades identificadas

**N-01 — Privacidad y soberanía de datos**
Los clientes de este perfil trabajan con material sin publicar que no debe salir de su control. Las soluciones en la nube (Google Drive, Dropbox, WeTransfer) implican que los datos pasan por servidores de terceros, quedando sujetos a sus políticas de privacidad, retención y posibles brechas de seguridad. La necesidad es disponer de una solución completamente auto-alojada donde los datos nunca abandonen la infraestructura propia.

**N-02 — Acceso remoto seguro sin exponer servicios**
Los miembros del equipo trabajan desde distintas ubicaciones. Publicar el servidor directamente en internet supone un riesgo de seguridad inaceptable. Se necesita un mecanismo de acceso remoto que no exponga ningún servicio web al exterior, pero que sea transparente para el usuario final.

**N-03 — Compatibilidad de formato automática**
Los vídeos en bruto llegan en distintos formatos y codecs (`.mkv`, `.mov`, `.avi`, y variantes de `.mp4`). Los editores y visualizadores web no siempre son compatibles con todos. La necesidad es disponer de un proceso automático que normalice los vídeos a un formato universalmente reproducible en navegadores y aplicaciones de edición, sin que el usuario tenga que hacer nada.

**N-04 — Gestión de vídeos corruptos sin intervención manual**
Una parte significativa del material proviene de grabadores de captura de pantalla (Nvidia Instant Replay, OBS con grabación circular) que a menudo generan ficheros con corrupción en los primeros fotogramas. El cliente no debe tener que diagnosticar ni reparar manualmente estos ficheros.

**N-05 — Visibilidad del estado de procesado**
El usuario sube un vídeo y necesita saber cuándo estará disponible el resultado. Sin retroalimentación visual, la experiencia es frustrante y genera dudas sobre si el proceso está funcionando. La necesidad es disponer de información en tiempo real del estado de procesado, sin salir de la interfaz de gestión de ficheros.

**N-06 — Coste de infraestructura mínimo y funcionamiento continuo**
El servidor debe funcionar de forma ininterrumpida (24/7) sin suponer un coste energético relevante. La solución hardware objetivo es un mini PC con procesador Intel N150, con un consumo aproximado de 6-10 W en carga, frente a los 80-150 W de un servidor convencional o los costes recurrentes de una instancia cloud.

### 2.3 Soluciones existentes y sus limitaciones

| Solución | Limitación respecto a las necesidades identificadas |
|---|---|
| Google Drive / Dropbox | Datos en servidores de terceros (N-01). Coste recurrente. Sin transcodificación automática (N-03). |
| Nextcloud (auto-alojado) | No incluye transcodificación automática ni gestión de corrupción (N-03, N-04). Sin barra de progreso de procesado (N-05). Complejidad de instalación elevada. |
| Jellyfin / Plex | Orientados al consumo de medios, no al intercambio de ficheros. Dependencia de internet para metadata. |
| Servidor FTP/SFTP propio | Sin interfaz web amigable (N-02, N-05). Sin transcodificación automática (N-03). |
| **PrivateClipServer** | **Cubre las 6 necesidades identificadas mediante una solución integrada, auto-alojada y de código abierto.** |

---

## 3. Solución adoptada

### 3.1 Visión general de la arquitectura

La solución se implementa como un stack de cuatro servicios Docker que comparten volúmenes y, en los casos necesarios, un espacio de red común. El diagrama siguiente refleja la arquitectura final:

```
                        ┌────────────────────────────────────────────────┐
                        │              Docker Host                       │
                        │                                                │
  Client (VPN)          │  ┌──────────┐     ┌───────────────────────┐    │
  ┌──────────┐          │  │WireGuard │     │       Watchers        │    │
  │WireGuard │◄─UDP────►│  │  :51820  │     │  video_processor      │    │
  │  Client  │          │  │ 10.0.0.1 │     │  keys_watcher         │    │
  └────┬─────┘          │  └───┬──────┘     └──────────┬────────────┘    │
       │                │      │ (shared network ns)   └───┐             │
       │                │      │                           │             │
       │ HTTP           │  ┌───┴──────────────────────┐    │ ffmpeg      │
       │ 10.0.0.1:8080  │  │        Nginx             │    ▼             │
       └───────────────►│  │  :8080 (reverse proxy)   │  /data/raw       │
                        │  │ + JS inject(progress bar)│    │             │
                        │  └────────┬─────────────────┘    ▼             │
                        │           │                    /data/processed │
                        │  ┌────────┴──────────────────┐ + status.json   │
                        │  │       FileBrowser         │                 │
                        │  │  :8081 (file manager UI)  │                 │
                        │  └───────────────────────────┘                 │
                        └────────────────────────────────────────────────┘
```

### 3.2 Justificación de las tecnologías elegidas

- **Docker y Docker Compose**
Se eligió Docker como plataforma de contenedores por la reproducibilidad del despliegue (un `docker compose up --build` es suficiente en cualquier máquina Linux compatible) y el aislamiento entre servicios. Docker Compose permite declarar toda la infraestructura en un único fichero `docker-compose.yml`, lo que simplifica el mantenimiento y la documentación.

- **WireGuard**
Se eligió WireGuard frente a OpenVPN por su menor huella en memoria y CPU, su base de código reducida (aprox. 4.000 líneas frente a las 600.000 de OpenVPN), su cifrado moderno (ChaCha20-Poly1305) y su configuración significativamente más simple. Estos factores son especialmente relevantes en hardware de bajo consumo como el Intel N150.

- **FileBrowser**
Proporciona una interfaz web completa de gestión de ficheros sin necesidad de desarrollar un frontend propio. Al compartir el espacio de red con el contenedor WireGuard (`network_mode: service:wireguard`), queda automáticamente aislado detrás de la VPN sin configuración adicional.

- **Nginx como reverse proxy**
La incorporación de Nginx permite inyectar JavaScript personalizado en las respuestas HTML de FileBrowser mediante la directiva `sub_filter`, sin modificar el código fuente de FileBrowser ni su imagen Docker. Esta decisión se tomó después de verificar que el sistema de branding nativo de FileBrowser (versiones 2.31.2 y 2.62) no inyecta JavaScript de forma fiable. Nginx además gestiona la ruta `/status/` que expone el fichero `status.json` al widget del navegador, devolviendo `{"active": false}` cuando el fichero no existe para evitar errores 404 en consola.

- **ffmpeg / ffprobe**
ffmpeg es el estándar de la industria para transcodificación de vídeo en entornos Linux. Se usa `libx264` como codec de vídeo por su compatibilidad universal con navegadores y reproductores. Los parámetros elegidos (`CRF 23`, `preset medium`, `AAC 192k`, `yuv420p`) representan el equilibrio óptimo entre calidad visual, tamaño de fichero y compatibilidad.

  - `H.264 / libx264` (motor de vídeo): estándar de compresión
  de vídeo más compatible. Reproducible en cualquier navegador
  moderno, televisor, móvil y aplicación de edición.
  - `CRF 23` (Constant Rate Factor): controla la calidad visual.
  Valor entre 0 (sin pérdidas) y 51 (máxima compresión).
  23 es el punto de equilibrio calidad/tamaño recomendado.
  - `preset medium` (velocidad de codificación): cuánto esfuerzo
  dedica el encoder a comprimir. A más lento, menor tamaño de
  fichero a igual calidad. `medium` es el equilibrio
  recomendado para uso general.
  - `AAC 192k` (motor de audio): formato de audio estándar en
  MP4. 192 kbps ofrece calidad transparente para voz y música.
  - `yuv420p` (formato de color): el más compatible para
  reproducción web y en dispositivos móviles. Algunos encoders
  producen `yuv444p` que no todos los navegadores soportan.

> **Nota sobre el motor de transcodificación y el hardware objetivo:** El motor actual (`libx264`) realiza la codificación por software a plena carga de CPU. Para el despliegue definitivo en el mini PC Intel N150 — objetivo de hardware de este proyecto — estaba previsto sustituirlo por el motor de aceleración por hardware del chip Intel (`h264_vaapi` vía VA-API), que delega la codificación al bloque Quick Sync Video integrado en el procesador, reduciendo drásticamente el consumo de CPU durante el procesado. Este cambio no se implementó en la versión actual porque no se dispuso del dispositivo N150 en tiempo para realizar pruebas reales sobre él. Se tomó la decisión de dejar el proyecto en un estado completamente testeado sobre hardware convencional antes de migrar al motor hardware, y documentar la adaptación como trabajo futuro inmediato.

- **inotifywait (inotify-tools)**
Se eligió `inotifywait` para la detección de nuevos ficheros en lugar de un bucle de polling periódico, porque es un mecanismo basado en eventos del kernel Linux (inotify) que no consume CPU cuando no hay actividad. El evento `close_write` garantiza que el fichero está completamente escrito antes de procesarse.

- **Bash como lenguaje de scripting**
Todos los scripts de automatización se implementaron en Bash puro, evitando deliberadamente dependencias externas como Python o Node.js, tanto para minimizar el tamaño de las imágenes Docker como para reducir el consumo de memoria en tiempo de ejecución. Únicamente ffmpeg y ffprobe (incluidos en el mismo paquete) se usan como procesos externos.

### 3.3 Descripción de los componentes del sistema

**Contenedor `wireguard`**
Gestiona el servidor VPN. En el primer arranque genera automáticamente las claves pública y privada y el fichero `wg0.conf` con la interfaz `10.0.0.1/24`. Expone el puerto `51820/UDP` al exterior. Todos los demás contenedores con acceso web (`filebrowser`, `nginx`) comparten su espacio de red mediante `network_mode: service:wireguard`, por lo que son inalcanzables desde el exterior de la VPN.

**Contenedor `filebrowser`**
Sirve la interfaz web de gestión de ficheros en el puerto interno `8081`. Tiene acceso de lectura/escritura a `/data/raw`, `/data/processed` y `/data/keys_inbox`.

**Contenedor `nginx`**
Escucha en el puerto `8080` (el único expuesto en el espacio de red de WireGuard). Actúa como proxy inverso hacia FileBrowser en `127.0.0.1:8081`, inyectando el script `injection_custom_progress_bar.js` antes del cierre de `</body>` en cada respuesta HTML. También sirve el fichero `status.json` desde `/data/processed/` bajo la ruta `/status/`.

**Contenedor `watchers`**
Ejecuta tres daemons en paralelo:

- `video_processor_watcher.sh`: Monitoriza `/data/raw/` con `inotifywait`. Cuando detecta un vídeo completamente subido (evento `close_write`), lo valida con `ffprobe` y lo añade a la cola en `/tmp/pcs_queue/`.
- `queue_processor.sh`: Procesa la cola FIFO. Por cada vídeo: ejecuta el algoritmo de corrección de corrupción (Remux-Trim), lanza `ffmpeg` para la transcodificación, y escribe el progreso en `status.json` mediante `progress_bar_writer.sh`.
- `keys_watcher.sh`: Monitoriza `/data/keys_inbox/`. Cuando el administrador deposita un fichero `.txt` con una clave pública WireGuard, llama a `add_peer.sh` para registrar automáticamente el nuevo peer en `wg0.conf` y reiniciar los contenedores afectados.

### 3.4 El algoritmo de corrección de corrupción (Remux-Trim)

Este componente representa la solución más técnicamente compleja del proyecto y resuelve un problema específico de vídeos generados por Nvidia Instant Replay y grabadores similares.

**Causa raíz del problema**
El vídeo H.264 se organiza en GOPs (Groups of Pictures): secuencias de fotogramas I (completos), P (predictivos hacia atrás) y B (predictivos bidireccionales). Cuando Nvidia Instant Replay guarda un clip cortando desde un buffer circular, frecuentemente empieza a mitad de un GOP — con fotogramas P o B que hacen referencia a un I-frame que no está en el fichero.

Adicionalmente, el fichero MP4 contiene un átomo `avcC` en su cabecera con los parámetros globales de decodificación (SPS/PPS). Cuando el clip fue cortado a mitad de GOP, el `avcC` también suele estar corrompido. Esto es determinante: ffmpeg lee el `avcC` en el momento de abrir el fichero, antes de leer ningún fotograma. Si el `avcC` está corrompido, el decoder queda "envenenado" desde el primer instante, haciendo que cualquier intento posterior de seek con `-ss` sea inútil — el decoder ya está roto.

**Por qué los enfoques anteriores fallaron**

El primer enfoque (buscar el primer I-frame con ffprobe y hacer seek con `-ss`) fallaba porque el problema no está en los fotogramas sino en el `avcC` de la cabecera: el decoder ya estaba roto antes de intentar el seek.

El segundo enfoque (decodificar chunks de 0.5s y contar errores específicos) fallaba porque las fronteras de los chunks no coincidían con las de los GOPs, generando falsos positivos en el conteo de errores.

**La solución implementada**
La idea clave es que si se hace un **remux** (copia de stream sin recodificación) desde una posición temporal concreta, ffmpeg genera un **nuevo `avcC` completamente limpio** basado únicamente en los fotogramas a partir de esa posición, ignorando por completo el `avcC` original corrompido.

```
Para cada segundo PROBE_T desde 0 hasta la duración:

  Paso 1 — Remux desde PROBE_T:
    ffmpeg -ss $PROBE_T -i input.mp4 -c copy TEST_FILE.mp4
    → Genera un fichero con un avcC fresco e independiente

  Paso 2 — Test-decodificación del fichero fresco:
    ERROR_LINES=$(ffmpeg -v error -t 2.0 -i TEST_FILE -frames:v 60 -f null /dev/null 2>&1 | wc -l)

  Si ERROR_LINES == 0:
    → Primer GOP limpio encontrado en PROBE_T segundos
    → Usar TEST_FILE como entrada del encode final
    → Parar el bucle

  Si ERROR_LINES > 0:
    → Seguir probando en PROBE_T + 1
```

Durante el escaneo, el widget de la barra de progreso muestra el estado `scanning` con la posición actual, para que el usuario sepa que el sistema está analizando el vídeo antes de procesarlo.

---

## 4. Actividades en que se divide la ejecución

### Fase 1 — Análisis, diseño y setup inicial
- Definición de requisitos y arquitectura del sistema
- Selección y justificación de tecnologías (WireGuard, FileBrowser, Docker)
- Configuración del entorno de desarrollo (WSL2 Ubuntu 22.04, Docker)
- Creación de la estructura de carpetas del repositorio

### Fase 2 — Infraestructura base: VPN y acceso web
- Implementación del contenedor WireGuard con generación automática de claves
- Implementación del contenedor FileBrowser con red compartida
- Script `add_peer.sh` para registro automático de clientes VPN
- Script `keys_watcher.sh` para detección automática de nuevas claves
- Scripts de cliente para Windows, Linux/macOS y móvil (generación del fichero `.conf`)

### Fase 3 — Pipeline de vídeo básico
- Implementación de `video_processor_watcher.sh` con `inotifywait`
- Integración de `ffmpeg` para transcodificación a H.264/AAC/yuv420p
- Pruebas de transcodificación con vídeos estándar

### Fase 4 — Corrección de vídeos corruptos (iteraciones)
- Diagnóstico del problema con vídeos Nvidia Instant Replay
- Primera iteración: seek por I-frame con ffprobe (descartada)
- Segunda iteración: escaneo por chunks de 0.5s (descartada)
- Tercera iteración: escaneo con conteo de errores mejorado (descartada)
- Iteración final: algoritmo Remux-Trim (implementada)
- Validación con múltiples vídeos corruptos reales

### Fase 5 — Sistema de cola FIFO
- Separación de responsabilidades: `video_processor_watcher.sh` (detección) y `queue_processor.sh` (procesado)
- Implementación de cola basada en ficheros en `/tmp/pcs_queue/`
- Gestión del `progress_bar_writer.sh` anterior para evitar escritores fantasma

### Fase 6 — Barra de progreso en tiempo real (iteraciones)
- Primera iteración: branding nativo de FileBrowser v2.62 (descartada)
- Segunda iteración: FileBrowser v2.31.2 con branding (descartada)
- Iteración final: incorporación de Nginx como reverse proxy con `sub_filter`
- Implementación de `progress_bar_writer.sh` con aritmética de punto fijo (sin awk)
- Widget JavaScript flotante con barra de progreso, ETA(Estimated Time of Arrival/ Tiempo estimado de llegada), velocidad y cola
- Servicio `/status/` en Nginx para exponer `status.json`
- Fallback en Nginx (`{"active": false}`) cuando no hay procesado activo

### Fase 7 — Pruebas de integración y de estress
- Pruebas de rendimiento con `htop` y `docker stats`
- Pruebas con múltiples clientes VPN simultáneos
- Pruebas desde dispositivos móviles con la app WireGuard
- Pruebas con usuarios finales reales (feedback recogido)
- Correcciones derivadas del feedback de usuarios

### Fase 8 — Documentación
- Redacción del README técnico con arquitectura, guía de uso y troubleshooting
- Redacción de la documentación formal del proyecto

---

## 5. Planificación de la ejecución

### 5.1 Metodología

El proyecto se desarrolló con una metodología iterativa basada en prueba-error-corrección, sin herramientas formales de gestión de proyectos. El control de versiones se realizó mediante Git, con commits al repositorio GitHub al finalizar cada fase estable. El feedback de usuarios finales (compañeros que probaron el sistema en condiciones reales) actuó como el principal mecanismo de validación y definición de nuevas funcionalidades(tales como la barra de progreso, la lista de pendientes, los scripts para la automatización de creación de ficheros para wireguard para los clientes, opiniones de uso...).

### 5.2 Distribución temporal

El proyecto se desarrolló en un período de **2 meses y 15 días**, con una dedicación de **5 días semanales** a razón de entre **5 y 8 horas diarias** (media de 6,5 horas/día), lo que supone aproximadamente **54 días de trabajo efectivo** y un total estimado de **350 horas**.

### 5.3 Diagrama de Gantt

```
Semana →         1     2     3     4     5     6     7     8     9     10    11
┌────────────────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│Fase 1          │█████│███  │     │     │     │     │     │     │     │     │     │
│Fase 2          │     │   ██│█████│███  │     │     │     │     │     │     │     │
│Fase 3          │     │     │     │   ██│███  │     │     │     │     │     │     │
│Fase 4          │     │     │     │     │   ██│█████│███  │     │     │     │     │
│Fase 5          │     │     │     │     │     │     │   ██│█    │     │     │     │
│Fase 6          │     │     │     │     │     │     │     │ ████│████ │     │     │
│Fase 7 (pruebas)│     │     │     │░░░  │ ░░ ░│░░░░░│░░░ ░│░   ░│░░░░ │     │     │
│Fase 8 (docs)   │     │     │     │     │     │     │     │     │    █│█████│██   │
└────────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
░ = pruebas parciales continuas a lo largo del desarrollo
```

### 5.4 Secuencia y dependencias entre fases

| Ref | Fase | Duración estimada | Fase anterior | Fase posterior |
|---|---|---|---|---|
| F1 | Análisis y setup | 1,5 semanas (~8 días) | — | F2 |
| F2 | Infraestructura VPN + FileBrowser | 2 semanas (~10 días) | F1 | F3 |
| F3 | Pipeline de vídeo básico | 1 semana (~5 días) | F2 | F4 |
| F4 | Corrección de corrupción | 2 semanas (~10 días) | F3 | F5 |
| F5 | Sistema de cola | 0,5 semanas (~3 días) | F4 | F6 |
| F6 | Barra de progreso | 1,5 semanas (~8 días) | F5 | F7 |
| F7 | Pruebas de integración | En simultáneo con otras Fases (~21 días) | [F2-F7] | F8 |
| F8 | Documentación | 1,5 semanas (~8 días) | F6 | — |

---

## 6. Seguimiento y control de la ejecución

> Esta sección documenta en detalle el proceso real de desarrollo: las decisiones técnicas adoptadas, los problemas encontrados, las soluciones probadas y los criterios que llevaron a descartar o adoptar cada una de ellas. Constituye el núcleo del proceso de aprendizaje técnico del proyecto.

### 6.1 Metodología de evaluación y control

Al no utilizarse herramientas formales de gestión de proyectos, el control de la ejecución se realizó mediante tres mecanismos:

1. **Prueba directa sobre el sistema**: cada cambio se verificaba levantando el stack con `docker compose up --build` y comprobando el comportamiento esperado.
2. **Logs de contenedores**: `docker logs -f <contenedor>` para depurar el comportamiento en tiempo real.
3. **Feedback de usuarios reales**: compañeros con distintos perfiles técnicos probaron el sistema en condiciones reales, reportando problemas de usabilidad y comportamientos inesperados.

Las versiones anteriores de los scripts (conservadas con sufijos `_1`, `_2`, `_3` en el repositorio) actúan como registro histórico de las iteraciones — equivalente a un historial de commits de ramas de desarrollo.

### 6.2 Iteraciones en el pipeline de vídeo

#### 6.2.1 Problema inicial: vídeos de Nvidia Instant Replay no procesables

**Versión 3 — `video_processor_watcher_3.sh` (primera iteración)**

Al probar con vídeos reales generados por Nvidia Instant Replay, ffmpeg devolvía consistentemente:

```
[mov,mp4,m4a] moov atom not found
Invalid data found when processing input
```

El problema se identificó como corrupción en el inicio del fichero. La solución intentada fue utilizar `ffprobe` para localizar el primer I-frame real del vídeo y usar el flag `-ss` de ffmpeg para empezar desde esa posición:

```bash
FIRST_KF=$(ffprobe -select_streams v:0 -show_packets -skip_frame nokey \
    -of csv=print_section=0 -show_entries packet=pts_time \
    -read_intervals "%+#1" "$INPUT" 2>/dev/null | head -1)

SEEK_FLAG="-ss $FIRST_KF"
```

**Resultado**: La solución no funcionó. El vídeo seguía fallando incluso al seekar al primer I-frame reportado por ffprobe.

**Análisis del fallo**: Investigando más en profundidad, se descubrió que el problema no residía únicamente en los fotogramas, sino en el átomo `avcC` de la cabecera del contenedor MP4. Este átomo almacena los parámetros globales de decodificación (SPS/PPS) y ffmpeg lo lee al **abrir el fichero**, antes de tocar ningún fotograma. Si el `avcC` está corrompido — cosa habitual en clips cortados a mitad de GOP — el decoder queda "envenenado" desde el inicio, haciendo que cualquier seek posterior sea inútil.

---

**Versión 2 — `video_processor_watcher_2.sh` (segunda iteración)**

Con el nuevo entendimiento del problema, se diseñó un enfoque diferente: en lugar de buscar el I-frame mediante metadatos, decodificar pequeños fragmentos de vídeo en ventanas de 0.5 segundos y contar los errores producidos, buscando la primera ventana sin errores:

```bash
ERRORS=$(ffmpeg -ss "$PROBE_T" -t 0.5 -v error -fflags +discardcorrupt \
    -i "$INPUT" -frames:v 4 -f null /dev/null 2>&1 | \
    grep -cE "overflow|Invalid NAL|no frame!|corrupt decoded|decode_slice_header error")
```

**Resultado**: Mejora parcial, pero el sistema producía falsos negativos en algunos vídeos.

**Análisis del fallo**: Las fronteras de las ventanas de 0.5 segundos no coincidían con las fronteras de los GOPs, lo que generaba lecturas ambiguas. Además, el mismo problema de `avcC` persistía — el decoder seguía envenenado al abrir el fichero original con `-i "$INPUT"`.

---

**Versión 1 — `video_processor_watcher_1.sh` (tercera iteración, misma rama de razonamiento)**

Se continuó con el mismo enfoque pero añadiendo dos mejoras:

1. **Guard de validación previa**: antes de intentar procesar, se valida el fichero con `ffprobe`. Si `ffprobe` no puede leer la duración, el fichero se descarta silenciosamente (resolvió el bucle infinito de intentos fallidos).
2. **Umbral de segundos ampliado a 60**.

**Resultado**: El guard funcionó para los casos de corrupción total, pero el problema fundamental del `avcC` seguía presente para casos de corrupción parcial.

---

**Versión actual — `video_processor_watcher.sh` + `queue_processor.sh` (iteración final)**

La solución definitiva fue: si se hace un **remux** (copia de stream sin recodificación) desde una posición temporal concreta, ffmpeg genera un **nuevo `avcC` completamente independiente** del original, basado únicamente en los frames a partir de esa posición. Esto elimina el envenenamiento del decoder porque el `avcC` del fichero de prueba es siempre fresco.

```bash
# Paso 1: remux desde PROBE_T → genera avcC limpio
ffmpeg -y -ss "$PROBE_T" -i "$INPUT" -c copy -avoid_negative_ts make_zero "$TEST_FILE"

# Paso 2: test-decode el fichero fresco (sin avcC corrompido)
ERROR_LINES=$(ffmpeg -v error -t 2.0 -i "$TEST_FILE" -frames:v 60 -f null /dev/null 2>&1 | wc -l)

if [ "$ERROR_LINES" -eq 0 ]; then
    ENCODE_INPUT="$TEST_FILE"  # primer GOP limpio encontrado
    break
fi
```

**Resultado**: Solución definitiva. Validada con múltiples vídeos corruptos reales de Nvidia Instant Replay.

Además, en esta iteración se separó la lógica en dos scripts independientes (`video_processor_watcher.sh` solo detecta y encola; `queue_processor.sh` solo procesa), aplicando el principio de responsabilidad única y permitiendo la gestión de cola FIFO.

### 6.3 Iteraciones en la barra de progreso

#### 6.3.1 Primera aproximación: sistema de branding nativo de FileBrowser

FileBrowser dispone de una funcionalidad de branding que, según la documentación, permite inyectar un fichero `custom.js` en todas las páginas servidas, apuntando a un directorio mediante la opción `--branding.files`. Se creó el `custom_progress_bar.js` y se configuró FileBrowser para cargarlo.

**FileBrowser v2.62 (instalación por defecto mediante el script oficial)**: el HTML servido incluía una etiqueta `<script></script>` vacía en el lugar donde debería aparecer el contenido del `custom.js`, pero el script nunca se inyectaba.

**FileBrowser v2.31.2 (versión pinada en el Dockerfile)**: mismo comportamiento.

**Diagnóstico**: Mediante `curl` sobre el endpoint `/branding/custom.js`, se comprobó que FileBrowser no servía el fichero en esa ruta — devolvía el HTML de la SPA en su lugar. La investigación concluyó que las versiones modernas de FileBrowser almacenan la configuración de branding en la base de datos SQLite interna, y que el mecanismo de inyección de JavaScript no funciona de forma fiable a través del fichero JSON de configuración.

---

#### 6.3.2 Iteración final: Nginx como reverse proxy con `sub_filter`

La solución fue incorporar Nginx como un cuarto contenedor, situado entre la VPN y FileBrowser. Nginx actúa como proxy inverso y, antes de devolver la respuesta HTML al navegador, sustituye `</body>` por `<script src="..."></script></body>` mediante la directiva `sub_filter`:

```nginx
location / {
    proxy_pass http://127.0.0.1:8081;
    proxy_set_header Host $host;           # pasa la cabecera Host original al backend
    proxy_set_header Accept-Encoding "";   # <- clave: desactiva gzip upstream
    sub_filter '</body>' '<script src="/branding/injection_custom_progress_bar.js"></script></body>';
    sub_filter_once on;
}
```

El detalle crítico es `proxy_set_header Accept-Encoding ""`: sin esta línea, FileBrowser devuelve el HTML comprimido con gzip, y `sub_filter` no puede realizar la sustitución en texto comprimido.

FileBrowser pasó a escuchar en el puerto interno `8081`, y Nginx expone el `8080` hacia la VPN.

Adicionalmente, se añadió en Nginx la ruta `/status/` con un fallback que devuelve `{"active": false}` cuando no existe el fichero `status.json`, evitando errores 404 en la consola del navegador del cliente.

**Resultado**: solución definitiva y funcional.

### 6.4 Iteraciones en el progress_bar_writer

#### 6.4.1 `progress_bar_writer_2.sh` (primera versión)

Versión básica funcional: leía el pipe de ffmpeg, calculaba porcentaje y ETA, y escribía `status.json`. Sin soporte de cola. Escritura directa al fichero sin atomicidad.

**Problema identificado**: en ocasiones el widget del navegador recibía JSON incompleto, produciendo errores de parseo. Causa: el navegador hacía `fetch` exactamente en el instante en que bash estaba escribiendo el fichero, leyendo un JSON a medias.

---

#### 6.4.2 `progress_bar_writer_1.sh` (segunda versión)

Se añadió soporte para la lista de vídeos en cola, necesaria para mostrar los vídeos pendientes en el widget. La lista se construía invocando Python3:

```bash
CURRENT_QUEUE=$(ls /tmp/pcs_queue/*_pending 2>/dev/null | sort | while read -r e; do cat "$e"; done | \
    python3 -c "import sys,json; lines=[...]; print(json.dumps(lines))")
```

**Problema identificado**: Python3 era una dependencia externa que se lanzaba como proceso separado cada 2 segundos. Esto contradecía el objetivo de eficiencia del proyecto. Además, añadía Python3 al Dockerfile de watchers innecesariamente.

---

#### 6.4.3 `progress_bar_writer.sh` (versión actual)

Se implementaron tres mejoras importantes:

**1 — Constructor JSON puro Bash (eliminación de Python3)**

```bash
build_queue_json() {
    local json="[" sep=""
    while IFS= read -r entry; do
        [ -f "$entry" ] || continue
        name=$(cat "$entry" 2>/dev/null)
        name="${name//\\/\\\\}"   # escape backslashes
        name="${name//\"/\\\"}"   # escape comillas dobles
        json="${json}${sep}\"${name}\""
        sep=","
    done < <(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort)
    echo "${json}]"
}
```

**2 — Escritura atómica del `status.json`**

```bash
printf '{"active":true,...}' ... > "${STATUS_FILE}.tmp"
mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
```

El `mv` dentro del mismo sistema de ficheros es una operación atómica a nivel de kernel: el fichero nunca existe en estado parcial. Elimina completamente la posibilidad de que el navegador lea un JSON incompleto.

**3 — Corrección del edge case `speed=N/A` y velocidades enteras**

ffmpeg ocasionalmente reporta `speed=N/A` en los primeros instantes del procesado. Si `SPEED_INT` resultaba vacío, la división aritmética de bash producía un error y el script se interrumpía. La solución implementada:

```bash
# Verificar si hay punto decimal antes de contar decimales
if [[ "$SPEED_NUM" == *.* ]]; then
    AFTER_DOT="${SPEED_NUM#*.}"
    DECIMAL_COUNT="${#AFTER_DOT}"
else
    DECIMAL_COUNT=0
fi

# Forzar base 10 para evitar interpretación octal (ej: "0956" → error)
SPEED_INT=$((10#${SPEED_INT:-0}))

# Guardia contra división por cero
if [ "$SPEED_INT" -gt 0 ] 2>/dev/null; then
    ETA_S=$(( ((DURATION - ELAPSED_S) * SCALE) / SPEED_INT ))
else
    ETA="--:--:--"
fi
```

### 6.5 Optimizaciones de rendimiento implementadas

**Eliminación de `awk`**: el cálculo de ETA requería división con decimales (la velocidad de ffmpeg se reporta como `1.80x`). La solución inicial usaba `awk` para la división flotante, lo que implica lanzar un proceso externo cada 2 segundos. Se sustituyó por aritmética de punto fijo en Bash puro:

```bash
# En lugar de: awk 'BEGIN { printf "%d", rem/spd }'
# Se usa aritmética entera escalada:
SCALE=$((10 ** DECIMAL_COUNT))
ETA_S=$(( ((DURATION - ELAPSED_S) * SCALE) / SPEED_INT ))
```

Esto elimina el ciclo completo de fork/exec/carga/ejecución/destrucción de proceso para un cálculo numérico trivial.

**Cola basada en ficheros en `/tmp`**: la cola no se almacena en disco persistente sino en RAM (tmpfs), reduciendo las escrituras al almacenamiento y la latencia de acceso.

**Guard de validación con ffprobe**: antes de encolar un vídeo, se valida su integridad con ffprobe. Esto evita que vídeos corruptos de forma irrecuperable o subidas incompletas entren en la cola y provoquen bucles de error.

### 6.6 Pruebas realizadas

| Tipo de prueba | Método | Resultado |
|---|---|---|
| Transcodificación básica | Subida de vídeos `.mp4`, `.mkv`, `.mov`, `.avi` | Correcto en todos los formatos |
| Corrección de corrupción | Vídeos reales de Nvidia Instant Replay | Algoritmo Remux-Trim detecta y corrige en < 10s (aprox)|
| Vídeos incompletos (moov atom) | Subida de fichero en mitad de copia | Guard de ffprobe descarta silenciosamente |
| Cola FIFO | Subida simultánea de 3 vídeos | Procesado en orden correcto |
| Prueba de estrés CPU | `htop` + `docker stats` durante procesado | Contenedor watchers ~320% CPU (de 400% total); resto del stack < 5% |
| Múltiples clientes VPN | 3 dispositivos simultáneos en la VPN | Sin degradación de servicio |
| Acceso desde móvil | App WireGuard (Android/iOS) + navegador | FileBrowser y widget de progreso funcionales |
| Feedback de usuarios finales | Pruebas con usuarios sin perfil técnico | Generó la idea de la barra de progreso y los scripts de cliente automatizados |
| Barra de progreso | Simulación manual de `status.json` + procesado real | Widget aparece, se actualiza y desaparece correctamente |

---

## 7. Conclusiones

### 7.1 Objetivos alcanzados

Todos los objetivos específicos definidos en la sección 1.2 han sido alcanzados en la versión actual del sistema:

- **OE-01**: WireGuard operativo con gestión automática de peers.
- **OE-02**: FileBrowser accesible exclusivamente desde dentro de la VPN.
- **OE-03**: Pipeline de transcodificación automático y funcional.
- **OE-04**: Algoritmo Remux-Trim operativo para vídeos corruptos de Nvidia Instant Replay.
- **OE-05**: Cola FIFO implementada y probada con múltiples vídeos simultáneos.
- **OE-06**: Barra de progreso en tiempo real integrada en FileBrowser vía Nginx.
- **OE-07**: El stack completo en reposo consume < 250 MB de RAM y < 5% de CPU; la arquitectura está diseñada para escalar hacia aceleración hardware en el N150.
- **OE-08**: Despliegue con un solo comando (`bash main_use.sh`) verificado.
- **OE-09**: README técnico completo redactado y mantenido.

### 7.2 Trabajo futuro

- **Inmediato — Aceleración hardware Intel Quick Sync (VA-API)**
La migración del motor de transcodificación de `libx264` (CPU puro) a `h264_vaapi` (Quick Sync del Intel N150) es el paso más impactante pendiente. Sobre el N150, este cambio reduciría el consumo de CPU durante el procesado de vídeo de ~320% a < 30%, convirtiendo la transcodificación en una tarea prácticamente transparente en términos energéticos. El cambio en ffmpeg es directo:

```bash
# Estado actual (CPU puro):
-c:v libx264 -crf 23 -preset medium

# Objetivo (Intel Quick Sync via VA-API):
-vaapi_device /dev/dri/renderD128
-vf 'format=nv12,hwupload'
-c:v h264_vaapi -qp 23
```

Requiere además exponer el dispositivo de renderizado en `docker-compose.yml`:
```yaml
devices:
  - /dev/dri:/dev/dri
```

- **Gestión de permisos de carpetas y usuarios**
FileBrowser permite crear múltiples usuarios con permisos diferenciados. Implementar una estructura de permisos que permita que distintos miembros del equipo tengan acceso solo a sus carpetas propias está identificado como mejora pendiente.

- **Reproducción de múltiples pistas de audio simultáneas en el navegador**
Algunos vídeos transcodificados contienen varias pistas de audio (comentario del autor, audio del juego, etc.). El navegador no reproduce múltiples pistas simultáneamente de forma nativa. Se ha identificado la necesidad de implementar un selector de pistas de audio en la interfaz o mezclar las pistas durante la transcodificación.

### 7.3 Reflexiones sobre el proceso

El aspecto más valioso del proceso de desarrollo fue la retroalimentación de usuarios reales. Dos funcionalidades centrales del sistema — la barra de progreso y los scripts de cliente automatizados — surgieron directamente de observar cómo usuarios sin perfil técnico interactuaban con versiones tempranas del sistema y encontraban puntos de fricción que desde la perspectiva del desarrollador no eran evidentes.

El problema de la corrupción de vídeos de Nvidia Instant Replay fue el reto técnico más significativo. La cadena de tres enfoques fallidos antes de llegar a la solución correcta ilustra la importancia de entender el problema a nivel del sistema (en este caso, el funcionamiento del átomo `avcC` en el contenedor MP4 y el ciclo de vida del decoder de ffmpeg) antes de intentar soluciones superficiales.

La decisión de escribir todos los scripts en Bash puro, evitando deliberadamente Python, awk (salvo en las primeras versiones), o cualquier otra dependencia de runtime, supuso un esfuerzo adicional en algunos casos (especialmente la aritmética de punto fijo y el constructor JSON puro Bash), pero garantiza que el sistema sea ejecutable en cualquier imagen Linux mínima sin dependencias adicionales, lo que es coherente con el objetivo de eficiencia en hardware de bajo consumo.

---

## 8. Presupuesto

### 8.1 Horas de trabajo

**Datos de referencia salarial**

| Concepto | Valor |
|---|---|
| Perfil profesional de referencia | Técnico Superior en ASIR / Administrador de Sistemas Junior |
| Salario bruto anual de referencia (España, 2026) | 22.000 € |
| Meses trabajados al año | 12 |
| Salario bruto mensual | 1.833,33 € |
| Días laborables por mes | 20 días |
| Horas por día (jornada estándar) | 8 h |
| Horas laborables por mes | 160 h |
| **Coste bruto por hora** | **11,46 €/h** (redondeado a 11,50 €/h) |

**Distribución de horas por fase**

| Fase | Descripción | Horas estimadas | Coste (11,50 €/h) |
|---|---|---|---|
| F1 | Análisis, diseño y setup inicial | 40 h | 460,00 € |
| F2 | Infraestructura VPN + FileBrowser | 63 h | 724,50 € |
| F3 | Pipeline de vídeo básico | 35 h | 402,50 € |
| F4 | Corrección de vídeos corruptos (4 iteraciones) | 84 h | 966,00 € |
| F5 | Sistema de cola FIFO | 21 h | 241,50 € |
| F6 | Barra de progreso (3 iteraciones) | 56 h | 644,00 € |
| F7 | Pruebas de integración y feedback | 21 h | 241,50 € |
| F8 | Documentación técnica y formal | 30 h | 345,00 € |
| **TOTAL(bruto)** | Total bruto| **350 h** | **4.025,00 €** |
| **TOTAL(neto(21%))** | Total neto, reducción del 21% | **350 h** | **3.179,75 €** |

> **Nota sobre el cálculo:** 54 días laborables × 6,5 h/día promedio = 351 h ≈ **350 h**. La distribución entre fases es estimada con base en el historial de iteraciones documentado en la sección 6.

### 8.2 Coste de hardware y software

| Concepto | Descripción | Coste |
|---|---|---|
| Mini PC Intel N150 | Hardware objetivo de despliegue (Beelink EQ12 o similar) | 160,00 € |
| Sistema operativo | Ubuntu Server 22.04 LTS | 0,00 € (open source) |
| Docker Engine | Motor de contenedores | 0,00 € (open source) |
| WireGuard | Software VPN | 0,00 € (open source) |
| FileBrowser | Interfaz web de ficheros | 0,00 € (open source) |
| Nginx | Reverse proxy | 0,00 € (open source) |
| ffmpeg / ffprobe | Motor de transcodificación | 0,00 € (open source) |
| **Subtotal hardware/software** | | **160,00 €** |

### 8.3 Resumen del presupuesto total

| Partida | Importe |
|---|---|
| Mano de obra (350 h × 11,50 €/h) | 4.025,00 € |
| Hardware (mini PC Intel N150) | 160,00 € |
| Software y licencias | 0,00 € |
| **TOTAL** | **4.185,00 €** |

> **Comparativa con soluciones en la nube:** Un servicio equivalente basado en almacenamiento en la nube con procesado de vídeo (p. ej., una instancia de cómputo cloud con 4 vCPUs + almacenamiento de objeto) tendría un coste recurrente de aproximadamente 40-80 €/mes. PrivateClipServer amortiza el coste de hardware en 2-4 meses y elimina el coste recurrente indefinidamente.

---

## 9. Bibliografía y repositorio

### Repositorio del proyecto

- **Código fuente**: https://github.com/Penguin1866s/PrivateClipServer/

### Documentación técnica de referencia

- WireGuard — Documentación oficial: https://www.wireguard.com/
- FileBrowser — Documentación oficial: https://filebrowser.org/
- Nginx — Directiva `sub_filter`: https://nginx.org/en/docs/http/ngx_http_sub_module.html
- ffmpeg — Documentación oficial: https://ffmpeg.org/documentation.html
- ffmpeg — Formato de salida `-progress`: https://ffmpeg.org/ffmpeg.html#Main-options
- Docker — Documentación oficial: https://docs.docker.com/
- inotify-tools — Página del proyecto: https://github.com/inotify-tools/inotify-tools

### Recursos técnicos consultados

- ffmpeg Wiki — H.264 Encoding Guide: https://trac.ffmpeg.org/wiki/Encode/H.264
- ffmpeg Wiki — Hardware Acceleration (VA-API): https://trac.ffmpeg.org/wiki/HWAccelIntro
- Intel — Quick Sync Video overview: https://www.intel.com/content/www/us/en/architecture-and-technology/quick-sync-video/quick-sync-video-general.html
- WireGuard Whitepaper: https://www.wireguard.com/papers/wireguard.pdf
- Nginx `sub_filter` con gzip — Stack Overflow: https://stackoverflow.com/questions/nginx-sub-filter-gzip

