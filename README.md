# Notchwatch

Notchwatch convierte el notch del Mac en una isla viva que, además de todo lo que hace [DynamicNotch](https://github.com/jackson-storm/DynamicNotch) (reproductor, descargas, AirDrop, batería, Bluetooth, Wi‑Fi, temporizador, pantalla de bloqueo…), **avisa con animación y sonido de las incidencias nuevas de Asana** y deja atenderlas sin salir del notch.

Es un fork de DynamicNotch, de Evgeniy Petrukovich, publicado bajo **GPL‑3.0**. Este proyecto conserva esa licencia: si alguna vez se distribuye fuera, hay que entregar el código fuente. El módulo de incidencias es nuestro; el resto es suyo y se mantiene lo más cerca posible del original para poder traer sus mejoras.

## El módulo «Incidencias»

- **Píldora con vida propia.** En reposo enseña el estado (color de la prioridad más alta pendiente) y el contador; respira, un brillo la recorre y de vez en cuando asoma la palabra «pendientes». Con altas o urgentes sin atender, el punto parpadea y la píldora resplandece del color de la prioridad.
- **Aviso al entrar una incidencia.** Tarjeta con prioridad, app, asunto, quién la reporta, módulo, errores de consola y vencimiento, y un sonido distinto por prioridad. Las bajas y medias se recogen solas; las altas y urgentes se quedan hasta que las atiendes y repiten el sonido.
- **Panel desplegado.** Lista de pendientes con filtro «Todas / Mías» y acciones al pasar el ratón: abrir en Asana, **en curso** (pone el estado «En curso» y te la asigna si no tiene responsable), posponer, **resolver** (pasa a Verificación y pone el estado «Solucionada») y, en el menú «…», asignármela, cambiar vencimiento, prioridad o marcar como vista.
- **Notificación de macOS** con las acciones Abrir, En curso, Asignármela y Posponer, y **atajo global** (⌃⌥⌘I por defecto) para desplegar o recoger la isla.
- **Control total desde Ajustes → Incidencias:** cuenta de Asana y proyectos (con asistente de alta), apariencia (tema, color por prioridad, icono y color por proyecto, tipografía, intensidad de movimiento), sonidos por prioridad y volumen, No molestar manual y por horario, duración de los avisos, intervalo de lectura, atajo, y exportar/importar el perfil para replicarlo en otro Mac.

### Otras cuentas y otras apps

La lógica vive en el paquete [`NotchwatchCore`](https://github.com/JoanDevandTech/notchwatch-core): un protocolo `IncidentSource` con colecciones, acciones y capacidades. Asana es la primera fuente; otra app se integra implementando ese protocolo, sin tocar la isla. La cuenta no está cableada: pega un token, la app lista tus workspaces y proyectos y propone qué sección es «Detectadas», cuál «Verificación» y qué campo es la prioridad. Tubuencamino queda como preajuste de un clic.

## Instalación

1. Descarga el `.dmg` de la última versión en **Releases** y arrastra Notchwatch a **Aplicaciones**.
2. La app va firmada con un certificado propio («Notchwatch Self-Signed»), no con un Developer ID de Apple, así que la primera vez Gatekeeper la bloquea: ábrela, ve a *Ajustes del Sistema → Privacidad y seguridad* y pulsa **Abrir igualmente** (o `xattr -dr com.apple.quarantine /Applications/Notchwatch.app`). Esto se repite con cada `.dmg` nuevo.
3. Concede los permisos que te pida para las funciones que uses (notificaciones para las incidencias; el resto son opcionales).
4. Abre *Ajustes → Incidencias → Cuenta y proyectos*, pega tu **token personal de Asana** (*Mi configuración → Apps → Consola de desarrolladores*) y elige **Usar preajuste de Tubuencamino** o **Configurar con el asistente**. El token solo se guarda en el Llavero.

Permisos ligados a la firma (Accesibilidad y Llavero): macOS asocia el permiso de *Accesibilidad* y el acceso al token de Asana en el Llavero a la firma de la app. Las versiones firmadas con el certificado propio mantienen siempre la misma identidad, así que al pasar a la primera de ellas (desde una ad‑hoc) macOS pide Accesibilidad y Llavero una última vez —vuelve a activar Notchwatch en *Privacidad y seguridad → Accesibilidad* y pulsa **Permitir siempre** en el aviso del Llavero— y ya no vuelve a preguntar en cada actualización. Las versiones ad‑hoc cambiaban de identidad en cada compilación y por eso lo pedían siempre. Gatekeeper, en cambio, sigue pidiendo **Abrir igualmente** con cada `.dmg` nuevo porque el certificado no es un Developer ID de Apple.

Requisitos: macOS 14.6 o superior. Funciona también sin notch (cápsula flotante).

## Desarrollo

Requisitos: Xcode 26 (macOS 15.6 o 26).

```bash
open DynamicNotch.xcodeproj      # esquema DynamicNotch; el producto se llama Notchwatch.app
./build_and_install_app.sh       # compila en Release y copia a /Applications
./build_dmg.sh                   # build/dmg/Notchwatch.dmg
```

Tests del módulo: esquema `DynamicNotch`, carpeta `DynamicNotchTests/Features/Incidents`. La CI (`macos-26`) compila, exige cero avisos en `Features/Incidents` y pasa esos tests más los de integración del motor. Con un tag `v*` (o lanzando *Release* a mano) se publica el DMG firmado con el certificado propio.

### Firma de las releases

La workflow `release.yml` compila sin firma de desarrollador y después re‑firma el `.app` entero (frameworks incluidos) con la identidad **Notchwatch Self-Signed**, importada en un llavero temporal que se borra al terminar. Usa dos secretos de *Settings → Secrets and variables → Actions*:

- `MACOS_CERT_P12_BASE64`: el `.p12` (certificado + clave privada) en base64, en una sola línea.
- `MACOS_CERT_PASSWORD`: la contraseña del `.p12`.

Si `MACOS_CERT_P12_BASE64` no existe o está vacío, la release se firma ad‑hoc como antes. Hardened runtime sigue desactivado (`ENABLE_HARDENED_RUNTIME=NO`).

Regenerar el certificado (solo si se pierde o caduca: cambiarlo hace que el Llavero vuelva a pedir permiso una vez):

```bash
cat > cert.cnf <<'CNF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = Notchwatch Self-Signed
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
openssl rand -base64 33 | tr -d '\n=' | tr '+/' 'AZ' > MACOS_CERT_PASSWORD.txt
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
# -legacy hace falta con OpenSSL 3; quítalo con LibreSSL/OpenSSL 1.1
openssl pkcs12 -export -legacy -name "Notchwatch Self-Signed" -inkey key.pem -in cert.pem \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout file:MACOS_CERT_PASSWORD.txt -out notchwatch-signing.p12
base64 -w0 notchwatch-signing.p12 > MACOS_CERT_P12_BASE64.txt   # en macOS: base64 -i notchwatch-signing.p12
rm key.pem
```

Sube el contenido de `MACOS_CERT_P12_BASE64.txt` y `MACOS_CERT_PASSWORD.txt` como los dos secretos y guarda el `.p12` y su contraseña fuera del repo. Para firmar en local con la misma identidad, importa el `.p12` en tu llavero y usa `SIGN_IDENTITY="Notchwatch Self-Signed" ./build_dmg.sh` (opcional `SIGN_KEYCHAIN=<ruta>`; por defecto `SIGN_IDENTITY=-`, ad‑hoc). `build_and_install_app.sh` acepta las mismas variables.

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
