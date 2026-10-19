# Sparekey

Una CLI de macOS para que un agente de IA desbloquee tu sesión iniciada y la vuelva a bloquear al terminar.

[![Licencia MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · Español

![Cubierta de Sparekey en una pantalla de Mac](docs/assets/cover.png)

## Características

- Desbloquea tu propia sesión con la contraseña guardada en el llavero de inicio de sesión.
- Verifica la cuenta de consola y el campo seguro antes de enviar la contraseña como máximo una vez por intento.
- Cubre las pantallas físicas por defecto. El agente puede manejar y capturar las aplicaciones que hay debajo.
- Mantiene la pantalla despierta hasta 60 minutos; termina al bloquear de nuevo o al tomar el control con autenticación.
- Incluye tokens de bloqueo por tarea, skills para Codex y Claude Code, y salida JSON.

Depende de la disposición de Accessibility de la pantalla de bloqueo. El destino de compilación macOS 13 o posterior no demuestra compatibilidad real con todas las versiones del sistema.

## Requisitos

- macOS 13 o posterior con tu propia sesión de escritorio iniciada.
- Xcode Command Line Tools con Swift 5.9 o posterior para compilar. La fórmula de Homebrew también compila desde el código fuente.
- Un terminal local interactivo en el Mac desbloqueado para setup y uninstall. Usa tu usuario habitual, sin `sudo`.
- Permiso de Accesibilidad para el helper instalado y acceso al llavero de inicio de sesión.
- Homebrew si eliges ese método de instalación.

No necesitas una cuenta de Apple Developer. Sparekey no desbloquea FileVault al arrancar, sesiones cerradas ni otras cuentas. Tampoco proporciona acceso remoto.

## Instalación

```sh
brew install yoonpooh/tap/sparekey
```

También puedes compilar desde el código fuente:

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Consulta la [instalación en inglés](README.md#installation) para añadir el helper a tu `PATH`.
La fórmula incluida en el repositorio es una plantilla con un marcador de checksum. No instales ese archivo directamente como una fórmula de publicación.

## Inicio rápido y uso

Tras instalar con Homebrew, configura desde tu propio terminal local:

```sh
sparekey setup --skill codex
```

Puedes elegir `--skill claude`, `--skill claude,codex` o `--no-skill`. Sin una opción de selección, setup pregunta qué skills instalar.
Setup crea o reutiliza una identidad de firma local, firma el helper, guarda la contraseña cuando hace falta e inicia un LaunchAgent de tu usuario.
Introduce la contraseña solo en los avisos ocultos del terminal. Si macOS pide usar la clave de firma, elige **Allow**, no **Always Allow**. Sigue las instrucciones para activar Accesibilidad para el helper.

```sh
sparekey doctor
sparekey status --json
```

Abre una conversación nueva con el agente después de instalar o actualizar la skill. Esta guía la comprobación de estado, probe, desbloqueo y limpieza.
Para una tarea manual en un Mac bloqueado, comprueba cada resultado antes de continuar:

```sh
sparekey probe --json
sparekey unlock --json
```

`probe` activa la pantalla y verifica el campo de contraseña sin leer ni enviar la contraseña.
Si la pantalla se despierta durante el período de gracia y devuelve `unlocked` con un `lockToken`, guarda ese token y omite `unlock`.
En caso contrario, conserva el token del desbloqueo correcto. Al terminar, usa únicamente el token recibido por tu tarea:

```sh
sparekey lock --lock-token "$TASK_LOCK_TOKEN" --json
```

`TASK_LOCK_TOKEN` es una variable de shell de ejemplo para el token devuelto, no una opción de configuración de Sparekey.
Una sesión que ya estaba desbloqueada no concede nueva autoridad para bloquear. Ante `relock_revoked`, conserva el estado actual. No uses `--force` como alternativa de limpieza.

## Configuración

Sparekey usa opciones de CLI en lugar de un archivo de configuración del usuario. La [configuración en inglés](README.md#configuration) enumera todas las rutas.

- El helper se instala en `~/Library/Application Support/sparekey/bin/sparekey`.
- La skill de Codex está en `~/.agents/skills/sparekey/SKILL.md` y la de Claude Code en `~/.claude/skills/sparekey/SKILL.md`.
- `setup --identity NAME` elige una identidad existente y `setup --reset-password` sustituye la contraseña guardada.
- `unlock --no-cover` omite la cubierta predeterminada para ese desbloqueo.
- Puedes añadir una skill con `sparekey skill install --agent codex` o `--agent claude`.

Sustituir una skill modificada requiere confirmación o `skill install --force`. Se guarda como `SKILL.md.bak` sin sobrescribir una copia existente.
Solo la migración de un antiguo plugin de Sparekey requiere Codex CLI; verifica su eliminación antes de escribir la skill. Una instalación nueva no necesita Codex CLI.

Después de actualizar o recompilar, ejecuta `sparekey setup` localmente para renovar el helper y las skills. Reutiliza la contraseña mientras siga siendo legible.
`sparekey uninstall`, desde un terminal local interactivo, elimina la instalación administrada y las skills cuyo contenido coincide.
La identidad de firma, la entrada de Accesibilidad, las skills modificadas, los enlaces creados manualmente y la CLI de Homebrew se eliminan por separado.

## Referencia de CLI

```sh
sparekey --help
sparekey help unlock
sparekey --version
```

La [referencia de CLI](docs/CLI.md) reúne la sintaxis, las opciones, los campos JSON, los códigos de salida y las reglas del token. Sin argumentos se muestra la ayuda.
`--json` funciona con `unlock`, `lock`, `status`, `probe` y `doctor`. Los códigos de salida son `0` para éxito, `1` para fallo operativo y `2` para uso incorrecto.

## Cómo funciona

La CLI envía solicitudes a un helper firmado mediante un socket Unix privado. Ambos extremos verifican el identificador del usuario del otro extremo.
El helper valida la sesión de consola, `loginwindow` firmado por Apple, la cuenta y el campo seguro antes de leer el llavero.
Un límite persistente de 30 segundos y un cortacircuitos tras un envío sin desbloqueo confirmado restringen los intentos posteriores.

La cubierta se coloca debajo de la pantalla de bloqueo antes de enviar la contraseña. **Unlock Mac** exige autenticación de macOS para mostrar la pantalla y revocar la autoridad de bloqueo de la tarea.
El token también caduca al recibir un evento de bloqueo del sistema, terminar la retención de pantalla o reiniciar el helper. El límite de 60 minutos termina la retención; no programa un bloqueo automático.
Consulta el [diseño](docs/DESIGN.md) y la [skill del agente](skills/sparekey/SKILL.md).

## Notas de seguridad

Lee la [política de seguridad](SECURITY.md) antes de instalar.

- Cualquier proceso de tu usuario puede solicitar el desbloqueo. Usa una cuenta personal de confianza.
- La cubierta no bloquea el Mac ni impide la entrada física a ciegas. No aparece en las capturas.
- El helper escucha en un socket local, no en la red. No protege contra malware que ya se ejecuta como tu usuario.
- No guardes contraseñas en chats, argumentos, variables de entorno ni documentos. Tampoco guardes tokens en registros o informes.
- No repitas desbloqueos fallidos en bucle ni evites las verificaciones. Informa de vulnerabilidades en privado según la política.

## Solución de problemas

Empieza con `sparekey doctor`. Un resultado correcto no verifica la disposición actual de la pantalla de bloqueo ni un desbloqueo real.

- `not_set_up`, `helper_not_running` o `helper_version_mismatch`: ejecuta `sparekey setup` localmente.
- `accessibility_missing`: autoriza el helper en Ajustes del Sistema > Privacidad y seguridad > Accesibilidad y repite setup.
- `credential_unavailable`: repite setup; si la contraseña está obsoleta, usa `sparekey setup --reset-password`.
- `breaker_tripped`, `unlock_not_confirmed` o `rate_limited`: detén los intentos repetidos y comprueba la causa.
- Ante errores de cuenta o de campo, no escribas en campos sin verificar. Con `relock_revoked`, conserva el estado actual.
- `display_sleep_not_confirmed`: puede que el bloqueo ya se haya completado. Lee `status` antes de actuar otra vez.

Un diálogo residual de Forzar salida puede causar un diseño no admitido. La [skill](skills/sparekey/SKILL.md) describe una recuperación limitada. Un fallo de probe no implica que se haya enviado una contraseña.

## Desarrollo

Desde la raíz del repositorio:

```sh
swift build
swift test
swift build -c release
python3 scripts/embed-agent-assets.py --check
```

`Package.swift` define el ejecutable, `SparekeyCore` y los tests de core y transporte. La comprobación de recursos compara la skill con el Swift generado.
El [renderizador de brillo](scripts/render-shimmer/README.md) genera imágenes sin operar el helper.
El [experimento de firma local](scripts/spike/README.md) modifica el llavero y LaunchAgent; ejecútalo solo de forma deliberada.
Consulta el [registro de cambios](CHANGELOG.md). La interacción con la pantalla de bloqueo se inspiró en [Cindy](https://github.com/makecindy/cindy); Sparekey es una implementación independiente.

## Licencia

[MIT](LICENSE), copyright yoonpooh.
