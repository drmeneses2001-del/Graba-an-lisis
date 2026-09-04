# Graba y Análisis

App para iPhone y iPad que graba lo que suena en el dispositivo, lo transcribe, lo analiza a fondo y entrega un PDF con resumen ejecutivo, propuestas, críticas, compromisos, decisiones, riesgos, cronología, tablas y gráficas. Todo vigilando el consumo de memoria con límites calculados para el aparato en el que corre.

## Qué hace

1. **Captura** el audio de dos formas:
   - **Todo el dispositivo** (extensión de difusión de ReplayKit): audio de las demás apps y micrófono, en **dos pistas separadas**. Así el informe distingue lo que dijo la otra parte de la llamada, el vídeo o el podcast («Interlocutor remoto») de lo que se dijo en la sala («Participante local»).
   - **Micrófono** desde la propia app, con la app en segundo plano. Recoge la sala y lo que sale por el altavoz.
2. **Transcribe** con el reconocimiento de voz de Apple, en ventanas solapadas, con opción de que el audio no salga nunca del aparato.
3. **Analiza** con uno de dos motores:
   - **En el dispositivo**: resumen extractivo, temas por frecuencia, clasificación de cada frase por marcadores de discurso (propuesta, crítica, compromiso, decisión, riesgo, pregunta), sentimiento, participación. Nada sale del aparato.
   - **Claude (nube)**: la transcripción se envía por bloques a la API de Anthropic con salida estructurada y se consolida en un solo informe. Mucho más rico; requiere clave propia.
4. **Genera un PDF** A4 con portada, índice con números de página, resumen ejecutivo con indicadores, gráficas vectoriales (participación, peso de temas, evolución del tono, compromisos por responsable y estado, críticas por gravedad, matriz de riesgos, cronología), tablas paginadas con cabecera repetida, citas, glosario, anexo con la transcripción y una sección de trazabilidad.

## Lo que iOS permite y lo que no

iOS **no** deja que una app lea la salida de audio de otras apps. No hay API para ello y no la habrá por diseño de privacidad. Las dos vías reales son las que usa esta app:

| Vía | Qué captura | Quién la inicia | Limitaciones |
|---|---|---|---|
| Extensión de difusión (ReplayKit) | Audio de todas las apps + micrófono, pistas separadas | El usuario, desde el botón de la app o el Centro de control | iOS silencia el audio protegido por DRM (Apple Music, algunos servicios de vídeo). La extensión vive con ~50 MB de RAM. |
| Micrófono en la app | Lo que suena en la sala y por el altavoz | La app | Calidad dependiente del entorno; una sola pista. |

Mientras la difusión está activa, iOS muestra la barra roja de estado. Es intencionado: el sistema garantiza que el usuario siempre sabe que se está grabando.

## Requisitos

- Xcode 15.4 o posterior, iOS 17 o posterior.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) para generar el proyecto (`brew install xcodegen`).
- Una cuenta de desarrollador con **App Groups** habilitado, imprescindible para que la extensión y la app compartan el audio.
- Opcional: una clave de la API de Anthropic para el motor en la nube.

## Puesta en marcha

```bash
git clone https://github.com/drmeneses2001-del/Graba-an-lisis
cd Graba-an-lisis
./Scripts/bootstrap.sh
open GrabaAnalisis.xcodeproj
```

Antes de compilar en un dispositivo real:

1. En **Signing & Capabilities** de los targets `GrabaAnalisis` y `BroadcastCapture`, selecciona tu equipo.
2. Cambia el prefijo `com.grabaanalisis` por el tuyo en `project.yml`, en los dos ficheros `.entitlements`, y en `RecorderViewModel.broadcastExtensionBundleID`. Vuelve a ejecutar `./Scripts/bootstrap.sh`.
3. Registra el App Group `group.com.grabaanalisis.shared` (o el tuyo) en ambos targets y en el portal de desarrolladores. Si cambias el identificador, actualízalo también en `AppGroup.identifier`.
4. Compila y ejecuta el esquema `GrabaAnalisis`. La extensión se instala con la app.

La difusión y el micrófono no funcionan en el simulador. El motor de análisis, el generador de PDF y los tests sí.

## Uso

**Grabar todo el dispositivo**: pestaña *Grabar* → «Todo el dispositivo» → pulsa el botón del sistema → elige «Graba y Análisis» → activa el micrófono si quieres tu voz → «Iniciar difusión». Para terminar, toca la barra roja o usa el Centro de control. Al volver a la app, la sesión aparece en *Sesiones*.

**Grabar con el micrófono**: pestaña *Grabar* → «Micrófono» → «Grabar». La app sigue grabando en segundo plano.

**Producir el informe**: abre la sesión → «Transcribir, analizar y generar PDF». El progreso muestra la fase, el porcentaje y la memoria en uso. El PDF se previsualiza dentro de la app y se comparte con la hoja del sistema.

**Motor en la nube**: *Ajustes* → Análisis → «Claude (nube)» → pega la clave → «Guardar clave» → «Probar». La clave se guarda en el llavero del dispositivo. La app usa el modelo `claude-opus-5` con razonamiento adaptativo y salida estructurada, y activa por defecto el reintento en modelo de reserva del servidor (`fallbacks: "default"`) para que una petición declinada por los clasificadores no deje la sesión sin informe. Si prefieres no usarlo, quita el parámetro `fallbacks` y la cabecera `anthropic-beta` en `ClaudeClient.complete`.

## Control de memoria

Es el requisito transversal del proyecto: ningún subsistema decide su propio tamaño de buffer, todos consultan al `MemoryGovernor`.

### Cómo se mide

- `MemoryReporter.footprintBytes()` lee `phys_footprint` con `task_info(TASK_VM_INFO)`. Es la cifra exacta contra la que iOS decide matar un proceso.
- `MemoryReporter.availableBytes()` usa `os_proc_available_memory()`: cuánto queda antes del límite. Cambia con lo que haya en segundo plano y con la temperatura.
- `DispatchSource.makeMemoryPressureSource` recibe los avisos del sistema (`warning`, `critical`).

### Límites por perfil de aparato

Los valores de partida dependen de la RAM física. Después se recortan con la memoria disponible en cada momento y el espacio libre en disco (el audio nunca puede ocupar más de un tercio del disco libre).

| Límite | Compacto (< 3,5 GB: iPhone SE, iPad básico) | Estándar (3,5–7 GB) | Pro (≥ 8 GB) |
|---|---|---|---|
| Duración máxima de sesión | 90 min | 3 h | 6 h |
| Audio por sesión | 400 MB | 900 MB | 2 GB |
| Ventana de reconocimiento | 30 s | 40 s | 45 s |
| Ventanas en paralelo | 1 | 1 | 2 |
| Lectura de audio por trozo | 64 KB | 128 KB | 256 KB |
| Texto de transcripción en memoria | 180 k caracteres | 450 k | 1,2 M |
| Bloque enviado al análisis | 12 k caracteres | 20 k | 28 k |
| Puntos por gráfica | 40 | 60 | 90 |
| Filas por tabla | 60 | 120 | 200 |
| Umbral de frenado | 70 % del presupuesto | 75 % | 80 % |

Con aviso de presión de memoria, todos los límites bajan a la mitad (con suelos para no romper la funcionalidad) y se avisa a los subsistemas para que suelten caché. Los límites vigentes se ven en *Ajustes › Límites de recursos*. El usuario puede recortar la duración máxima, nunca ampliarla.

### Dónde se aplica

| Pieza | Estrategia |
|---|---|
| Extensión de difusión | Tope propio de **38 MB** (el sistema mata a ~50). Cada `CMSampleBuffer` se convierte a 16 kHz mono Int16 y se escribe a disco sin copia (`Data(bytesNoCopy:)`); el conversor y el buffer de salida se reutilizan; no hay acumulación. Si la huella supera el tope, la difusión se cierra sola con un mensaje y el audio queda guardado. |
| Grabación por micrófono | Tap de `AVAudioEngine` dimensionado según el perfil; conversión y escritura inmediatas. |
| Transcripción | El fichero PCM se recorre en ventanas solapadas; solo una ventana está en memoria. Antes de cada ventana se comprueba el margen y, si hay presión, se espera. |
| Análisis en el dispositivo | Si la transcripción excede el presupuesto de caracteres, se analiza una muestra uniforme y el informe lo declara. |
| Análisis con Claude | La transcripción se trocea por bloques del tamaño que permite el perfil; se acumula solo el JSON de cada bloque. |
| PDF | Se escribe directamente a disco con `writePDF(to:)`, página a página. Las gráficas son vectoriales: ningún bitmap intermedio. Dos pasadas: una en seco para numerar el índice y otra real. |
| Almacenamiento | Ficheros planos por sesión (PCM crudo, JSON, PDF). Nada se carga entero: se lee por trozos. |

## Arquitectura

```
Sources/
├── App/                       Interfaz SwiftUI
│   ├── GrabaAnalisisApp.swift
│   ├── ViewModels/RecorderViewModel.swift
│   └── Views/                 Grabar, Sesiones, Detalle (PDF/Análisis/Transcripción), Ajustes
├── BroadcastExtension/        Extensión de ReplayKit (SampleHandler)
└── Core/
    ├── Shared/                App Group, modelos de sesión, almacén, ajustes, traspaso extensión→app
    ├── Memory/                MemoryReporter, DeviceClass + ResourceLimits, MemoryGovernor
    ├── Audio/                 Formato canónico, escritor/lector PCM, conversor, grabación por micrófono
    ├── Transcription/         Modelos y servicio sobre SFSpeechRecognizer
    ├── Analysis/              Modelos del informe, motor en el dispositivo, cliente y motor Claude, pipeline
    └── Report/                Tema, modelo de bloques, motor de texto, compositor, paginador, gráficas
Tests/GrabaAnalisisTests/      Límites, analizador en el dispositivo, generador de PDF
```

Flujo de una sesión:

```
Audio (ReplayKit o micrófono) ─▶ audio_device.pcm / audio_local.pcm
        ─▶ SpeechTranscriptionService ─▶ transcript.json
        ─▶ OnDeviceAnalyzer | ClaudeAnalyzer ─▶ analysis.json
        ─▶ ReportComposer ─▶ [ReportBlock] ─▶ PDFReportRenderer ─▶ informe.pdf
```

### El informe

Secciones que se emiten cuando hay contenido: Resumen ejecutivo (indicadores, resumen, puntos clave, clima de la sesión) · Panorama (reparto del tiempo hablado, detalle por interlocutor, evolución del tono) · Temas · Propuestas · Críticas y objeciones · Decisiones · Compromisos · Riesgos (matriz + tabla) · Pendiente (próximos pasos, preguntas abiertas) · Cronología · Citas y glosario · Anexo con la transcripción · Metodología y trazabilidad.

Las gráficas siguen unas reglas fijas: un solo eje, marcas finas con el extremo redondeado, separación de 2 pt entre rellenos, rejilla discreta, valor escrito junto a cada marca, leyenda cuando hay más de una serie, nunca más de tres series con color y nunca un color de estado reutilizado como serie. La paleta está validada para daltonismo y el informe se lee igual impreso en blanco y negro porque el color nunca es el único portador de información.

## Privacidad

- El audio y la transcripción no salen del dispositivo salvo que se active el motor en la nube; en ese caso se envía solo texto, nunca audio.
- Con «Solo en el dispositivo» activo, el reconocimiento de voz tampoco usa red.
- La clave de API vive en el llavero. No hay analítica ni telemetría.
- Grabar a otras personas puede requerir su consentimiento según la legislación aplicable. La app lo recuerda en la portada del PDF.

## Tests

En Xcode: `⌘U` con el esquema `GrabaAnalisis`. Cubren la monotonía y degradación de los límites, la extracción de cada categoría por el motor en el dispositivo, el respeto del presupuesto de caracteres y la generación de un PDF multipágina con el índice y el «Página N de M» correctos.

## Limitaciones conocidas

- El motor en el dispositivo es heurístico: reconoce fórmulas («propongo», «me comprometo», «no estoy de acuerdo»…) y no interpreta ironía ni contexto implícito. El PDF lo declara en la sección de trazabilidad.
- La atribución de hablante se basa en la pista de audio. Si dos personas hablan por el mismo micrófono, aparecen como un solo «Participante local».
- El reconocedor de Apple no admite todos los idiomas en modo estrictamente local; si el idioma elegido no está descargado, la app avisa.
- La extensión no graba vídeo a propósito: multiplicaría el consumo sin aportar nada al análisis.
