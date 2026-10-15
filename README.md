# Notchwatch

Notchwatch convierte el notch del Mac en una isla viva que, además de todo lo que hace [DynamicNotch](https://github.com/jackson-storm/DynamicNotch) (reproductor, descargas, AirDrop, batería, Bluetooth, Wi‑Fi, temporizador, pantalla de bloqueo…), **avisa con animación y sonido de las incidencias nuevas de Asana** y deja atenderlas sin salir del notch.

Es un fork de DynamicNotch, de Evgeniy Petrukovich, publicado bajo **GPL‑3.0**. Este proyecto conserva esa licencia: si alguna vez se distribuye fuera, hay que entregar el código fuente. El módulo de incidencias es nuestro; el resto es suyo y se mantiene lo más cerca posible del original para poder traer sus mejoras.

## El módulo «Incidencias»

- **Píldora con vida propia.** En reposo enseña el estado (color de la prioridad más alta pendiente) y el contador; respira, un brillo la recorre y de vez en cuando asoma la palabra «pendientes». Con altas o urgentes sin atender, el punto parpadea y la píldora resplandece del color de la prioridad.
- **Aviso al entrar una incidencia.** Tarjeta con prioridad, app, asunto, quién la reporta, módulo, errores de consola y vencimiento, y un sonido distinto por prioridad. Las bajas y medias se recogen solas; las altas y urgentes se quedan hasta que las atiendes y repiten el sonido.
- **Panel desplegado.** Lista de pendientes con filtro «Todas / Mías» y acciones al pasar el ratón: abrir en Asana, asignármela, posponer, **resolver** (pasa a Verificación) y, en el menú «…», cambiar vencimiento, prioridad o marcar como vista.
- **Notificación de macOS** con las acciones Abrir, Asignármela y Posponer, y **atajo global** (⌃⌥⌘I por defecto) para desplegar o recoger la isla.
- **Control total desde Ajustes → Incidencias:** cuenta de Asana y proyectos (con asistente de alta), apariencia (tema, color por prioridad, icono y color por proyecto, tipografía, intensidad de movimiento), sonidos por prioridad y volumen, No molestar manual y por horario, duración de los avisos, intervalo de lectura, atajo, y exportar/importar el perfil para replicarlo en otro Mac.

### Otras cuentas y otras apps

La lógica vive en el paquete [`NotchwatchCore`](https://github.com/JoanDevandTech/notchwatch-core): un protocolo `IncidentSource` con colecciones, acciones y capacidades. Asana es la primera fuente; otra app se integra implementando ese protocolo, sin tocar la isla. La cuenta no está cableada: pega un token, la app lista tus workspaces y proyectos y propone qué sección es «Detectadas», cuál «Verificación» y qué campo es la prioridad. Tubuencamino queda como preajuste de un clic.

## Instalación

1. Descarga el `.dmg` de la última versión en **Releases** y arrastra Notchwatch a **Aplicaciones**.
2. La app va firmada ad‑hoc, así que la primera vez macOS la bloquea: ábrela, ve a *Ajustes del Sistema → Privacidad y seguridad* y pulsa **Abrir igualmente** (o `xattr -dr com.apple.quarantine /Applications/Notchwatch.app`).
3. Concede los permisos que te pida para las funciones que uses (notificaciones para las incidencias; el resto son opcionales).
4. Abre *Ajustes → Incidencias → Cuenta y proyectos*, pega tu **token personal de Asana** (*Mi configuración → Apps → Consola de desarrolladores*) y elige **Usar preajuste de Tubuencamino** o **Configurar con el asistente**. El token solo se guarda en el Llavero.

Requisitos: macOS 14.6 o superior. Funciona también sin notch (cápsula flotante).

## Desarrollo

Requisitos: Xcode 26 (macOS 15.6 o 26).

```bash
open DynamicNotch.xcodeproj      # esquema DynamicNotch; el producto se llama Notchwatch.app
./build_and_install_app.sh       # compila en Release y copia a /Applications
./build_dmg.sh                   # build/dmg/Notchwatch.dmg
```

Tests del módulo: esquema `DynamicNotch`, carpeta `DynamicNotchTests/Features/Incidents`. La CI (`macos-26`) compila, exige cero avisos en `Features/Incidents` y pasa esos tests más los de integración del motor. Con un tag `v*` se publica el DMG firmado ad‑hoc.

### Dónde está cada cosa

```
DynamicNotch/Features/Incidents/
  Content/        Contenidos del motor: píldora/panel (live activity) y tarjeta de aviso (alerta)
  EventHandlers/  Decide qué enseña el notch: siempre la píldora; alerta o pulso según el estado
  ViewModels/     IncidentsViewModel: lectura, acciones optimistas, sonido, notificaciones, atajo
  Services/       Monitor (NotchwatchCore), perfil JSON, Llavero, notificaciones, atajo Carbon, sonidos
  Views/          Píldora, animaciones ambientales, alerta, panel, filas, componentes
  Design/         Tokens visuales (IncidentsTheme) y medidas (IncidentsLayout)
  Settings/       Sección de Ajustes con sus subpáginas y el asistente de alta de Asana
```

El perfil se guarda en `~/Library/Application Support/Notchwatch/profile.json` (sin tokens) y las vistas/pospuestas en `seen.json`.

### Traer cambios del DynamicNotch original

```bash
git remote add upstream https://github.com/jackson-storm/DynamicNotch.git
git fetch upstream && git merge upstream/main
```

Nuestros cambios fuera del módulo son pocos y están localizados: registro y prioridad del contenido, contenedor, coordinador de eventos, observadores de arranque, exclusión de gestos en `NotchInteractiveBodyView`, sección de Ajustes y el catálogo de cadenas (claves `incidents.*`). Identidad: bundle `com.joandev.notchwatch`, producto `Notchwatch`, feed de Sparkle propio.

### Pendiente antes de publicar actualizaciones automáticas

Sparkle apunta al `appcast.xml` de este repo, que está vacío. Para activarlo hay que generar un par de claves EdDSA con `generate_keys` de Sparkle, poner la pública en `SUPublicEDKey` (Info.plist) y firmar cada release.

## Licencia

GPL‑3.0, como el proyecto original. Consulta `LICENSE`.
