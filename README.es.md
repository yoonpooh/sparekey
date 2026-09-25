<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="140">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>Una llave de repuesto de tu Mac para tu agente de IA.</strong><br>
  Desbloquea la pantalla, termina el trabajo y vuelve a bloquearla.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black.svg" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift 5.9+">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-CN.md">简体中文</a> · Español
</p>

<p align="center">
  <sub>Última versión: <strong>0.2.0</strong>, que cubre la pantalla mientras trabaja el agente. Consulta el <a href="CHANGELOG.md">registro de cambios</a>.</sub>
</p>

<p align="center">
  <img src="docs/assets/cover.png" alt="Cubierta de pantalla de Sparekey en un Mac" width="720">
</p>

## Por qué Sparekey

Los agentes que manejan el ordenador o el navegador se detienen en cuanto el Mac se bloquea. O dejas el Mac desbloqueado durante horas, o vuelves y descubres que la tarea nunca llegó a ejecutarse.

Sparekey es una pequeña CLI para macOS que permite a un agente desbloquear **tu propia sesión, ya iniciada**, con una contraseña guardada en local, terminar su tarea y volver a bloquearla. Mientras el agente trabaja, una cubierta negra tapa las pantallas físicas para que nadie cercano vea lo que ocurre.

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

Con la skill de agente incluida, no tienes que explicarle nada de esto. Pídele una tarea de GUI normal en un Mac bloqueado y el agente comprobará el bloqueo, desbloqueará, hará el trabajo y volverá a bloquear la pantalla por su cuenta.

### Lo que no es

Sparekey no sirve para eludir contraseñas, recuperar cuentas ni ofrecer acceso remoto. No puede desbloquear FileVault durante el arranque, una sesión cerrada, la cuenta de otro usuario ni un Mac en reposo al que no se pueda acceder.

> [!WARNING]
> **Estado: fase temprana (0.2.0).** Funciona en macOS 27.2 con Apple silicon, donde dos ejecuciones del agente sin instrucciones adicionales desbloquearon el Mac, trabajaron y lo volvieron a bloquear correctamente. No se han probado otras versiones de macOS. Depende de la disposición de Accessibility de la pantalla de bloqueo, no de una API pública de desbloqueo.

## Inicio rápido

Necesitas macOS 13 o posterior con una sesión de escritorio iniciada, Xcode Command Line Tools con Swift 5.9 o posterior y un terminal local en el Mac para la configuración inicial. No hace falta una cuenta de Apple Developer.

**1. Instala** con Homebrew (compila desde el código fuente en tu Mac):

```sh
brew install yoonpooh/tap/sparekey
```

**2. Configura** desde un terminal local con el Mac desbloqueado, no por SSH:

```sh
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

Cuando macOS pida usar la clave de firma, haz clic en **Allow**, no en **Always Allow**. Escribe tu contraseña de inicio de sesión en el aviso oculto que muestra setup.

**3. Úsalo.** Pide a tu agente una tarea de GUI o pruébalo tú mismo:

```sh
sparekey status   # locked or unlocked
sparekey doctor   # check the install
```

**O pídeselo a tu agente.** Pega esto en Codex, Claude Code u otro agente. Instalará Sparekey y te dejará solo el paso de setup, porque la contraseña debe escribirse en tu propia terminal:

```text
Install Sparekey on this Mac: https://github.com/yoonpooh/sparekey
1. Run `brew install yoonpooh/tap/sparekey`.
2. Setup asks for my login password, so don't run `sparekey setup` yourself.
   Tell me the exact command to run in my own terminal, with the --skill
   option for the agent you are, and wait until I say it's done.
3. Run `sparekey doctor` and report the result.
Never ask me for the password.
```

<details>
<summary><strong>Compilar desde el código fuente</strong></summary>

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Después añade `sparekey` a tu `PATH`:

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

</details>

<details>
<summary><strong>Qué hace setup</strong></summary>

1. Crea una identidad `sparekey local signing` en tu llavero de inicio de sesión (solo la primera vez).
2. Firma e instala el helper en `~/Library/Application Support/sparekey/bin/sparekey`.
   - Cuando macOS pida usar la clave de firma, haz clic en **Allow**, no en **Always Allow**.
3. Pide tu contraseña de inicio de sesión dos veces. No se muestra al escribirla y se comprueba con macOS.
   - Nunca la pegues en un chat, en un argumento de comando ni en una variable de entorno.
4. Inicia el helper en segundo plano e instala la skill de agente que elegiste.
5. Te guía para activar **Accessibility** para el helper: abre el panel de ajustes, muestra el archivo en Finder, copia su ruta y vuelve a comprobarlo cuando lo actives.

</details>

### Actualizar

Después de `brew upgrade sparekey` o de recompilar, vuelve a ejecutar `sparekey setup`. Hasta entonces, la nueva CLI informa de `helper_version_mismatch`. Setup renueva el helper firmado sin pedir la contraseña, salvo que el helper ya no pueda leerla.

## Características

- **Desbloqueo y bloqueo verificados.** `unlock` envía la contraseña una sola vez y confirma el nuevo estado; `lock` bloquea y lo confirma. Si ya está bloqueado, no hace nada.
- **Cubierta de pantalla.** Inspirada en Locked Computer Use de Codex. Una cubierta negra con el logotipo de Sparekey, el mensaje «Your agent is using this Mac» y un botón **Lock Mac** tapa las pantallas físicas mientras trabaja el agente.
  - Se coloca debajo de la pantalla de bloqueo **antes** de enviar la contraseña, así que el escritorio nunca queda a la vista ni por un instante.
  - Las capturas y grabaciones de pantalla la excluyen: el agente sigue viendo la pantalla real y sus clics y pulsaciones llegan a las apps de debajo.
  - Un clic en **Lock Mac** bloquea el Mac. `sparekey lock` o cualquier otro bloqueo la retira.
  - `sparekey unlock --no-cover` la omite. La cubierta oculta la pantalla, pero no la bloquea.
- **Pantalla despierta.** Tras un desbloqueo confirmado, la pantalla no entra en reposo hasta `sparekey lock`, cualquier otro bloqueo o 60 minutos, para que el reposo por inactividad no bloquee el Mac a mitad de la tarea.
- **Recuperación de la pantalla de bloqueo.** Si la pantalla bloqueada está encendida pero muestra solo el fondo y el reloj en lugar de tu cuenta, Sparekey hace un ciclo de reposo→activación de la pantalla para recuperar la cuenta. Nunca escribe en una pantalla que no haya verificado.
- **Se detiene ante lo inesperado.** Como máximo un envío de contraseña, un límite de 30 segundos entre intentos y un cortacircuitos tras un desbloqueo no confirmado.
- **Skills de agente** para Codex y Claude Code, y salida `--json` para scripts.

## Cómo funciona

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` copia el binario a una ubicación fija, lo firma con una identidad de firma de código local y lo ejecuta como helper en segundo plano para tu usuario.
- La contraseña se guarda en tu llavero de inicio de sesión. Solo ese helper firmado puede leerla.
- El helper solo rellena un campo de contraseña verificado, envía **como máximo una vez** y se detiene de forma segura ante cualquier cosa inesperada: otras cuentas, diálogos, pantallas de recuperación o cambios de diseño.
- Un límite persistente de 30 segundos y un cortacircuitos evitan que una contraseña obsoleta acumule inicios de sesión fallidos.

Las notas de diseño están en [docs/DESIGN.md](docs/DESIGN.md).

## Skills de agente

Setup puede instalar una skill para **Codex** (`~/.agents/skills/sparekey`) y **Claude Code** (`~/.claude/skills/sparekey`). También puedes instalarla más tarde:

```sh
sparekey skill install --agent codex   # or: --agent claude
```

La skill indica al agente que:

- compruebe el estado de bloqueo antes del trabajo de GUI, o en cuanto falle el acceso a una app o ventana;
- desbloquee una vez, lo verifique y haga la tarea;
- vuelva a bloquear al terminar, aunque la tarea falle, pero solo si fue él quien desbloqueó el Mac;
- se detenga e informe de los errores en lugar de reintentar.

Pedir un trabajo de GUI equivale a dar permiso para desbloquear durante esa tarea. Si quieres que el Mac quede bloqueado o desbloqueado al final, díselo al agente.

### Autorízalo de antemano en las instrucciones del agente

En configuraciones con varios agentes, un orquestador puede decirles a sus agentes que no toquen el bloqueo, o un agente puede detenerse a pedir permiso. Para evitarlo, añade esto a tu `CLAUDE.md`, `AGENTS.md` o al prompt de sistema del orquestador:

```text
Screen lock: I pre-authorize unlocking this Mac with the sparekey skill
for any task that needs the screen. Use it without asking, and never
restrict this when delegating to other agents.
```

Sin esta línea, la skill igualmente desbloquea para los trabajos de GUI que pidas. La línea evita que ese permiso se pierda o se vuelva a consultar por el camino.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `sparekey unlock [--no-cover]` | Desbloquea una vez, confirma el estado, cubre las pantallas físicas por defecto y mantiene la pantalla despierta hasta `lock` o 60 minutos |
| `sparekey lock` | Bloquea y lo confirma; si ya está bloqueado, no hace nada |
| `sparekey status` | Muestra `locked` o `unlocked` |
| `sparekey probe` | Activa la pantalla y comprueba el campo de contraseña sin leer la contraseña |
| `sparekey setup` | Instala o renueva el helper, la credencial y las skills. Opciones: `--skill`, `--no-skill`, `--reset-password`, `--identity NAME` |
| `sparekey doctor` | Revisa la instalación, la firma, el helper, Accessibility, la credencial y las skills |
| `sparekey skill install` | Instala la skill de agente. Opciones: `--agent claude\|codex`, `--force` |
| `sparekey uninstall` | Elimina el helper, la credencial, el LaunchAgent y las skills escritas por Sparekey |
| `sparekey help [command]` | Muestra la ayuda |
| `sparekey version` | Muestra la versión |

Ejecutar `sparekey` sin argumentos muestra la ayuda; nunca desbloquea.

<details>
<summary><strong>Salida JSON, códigos de salida y códigos de error</strong></summary>

`unlock`, `lock`, `status`, `probe` y `doctor` aceptan `--json`:

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

Códigos de salida: `0` éxito, `1` fallo operativo, `2` error de uso. Un `status` correcto puede informar de cualquiera de los dos estados, así que revisa `state`.

Códigos de error: `usage`, `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `no_console_session`, `accessibility_missing`, `credential_unavailable`, `login_window_unsupported`, `field_not_ready`, `cover_unavailable`, `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`, `lock_not_confirmed`, `internal`. `doctor --json` también puede informar de `skill_outdated` y añade un mapa `statuses` por comprobación (`ok`, `warn`, `fail`, `skip`).

</details>

## Preguntas frecuentes y solución de problemas

Empieza por `sparekey doctor`. Cada fila con error indica cómo solucionarlo.

**¿La cubierta bloquea mi Mac?**
No. Oculta la pantalla, pero no la bloquea. Haz clic en **Lock Mac** en la cubierta o ejecuta `sparekey lock`.

**¿Por qué no veo la cubierta en las capturas del agente?**
Es intencionado. Las capturas y grabaciones de pantalla excluyen la cubierta, así que el agente ve la pantalla real.

**La pantalla de bloqueo solo muestra el fondo y el reloj.**
Sparekey hace un ciclo de reposo→activación de la pantalla para recuperar la cuenta. Nunca escribe en una pantalla que no haya verificado.

**`helper_version_mismatch`**
La CLI se actualizó o recompiló, pero el helper no. Vuelve a ejecutar `sparekey setup`.

**Falta Accessibility**
Activa `~/Library/Application Support/sparekey/bin/sparekey` en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Si acabas de activarlo, vuelve a ejecutar `setup` o reinicia el helper:

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"
```

**`breaker_tripped` o `unlock_not_confirmed`**
Puede que la contraseña guardada ya no sea correcta, por ejemplo si la cambiaste. Ejecuta `sparekey setup --reset-password` en local.

**`credential_unavailable` tras una actualización**
Vuelve a ejecutar `sparekey setup` e introduce la contraseña cuando te la pida.

**`rate_limited`**
Hubo un intento en los últimos 30 segundos. No lo repitas en bucle.

## Seguridad

Lee [SECURITY.md](SECURITY.md) antes de instalar. En resumen:

- **Cualquier proceso que se ejecute con tu usuario puede pedir al helper que desbloquee.** Sparekey está pensado para una cuenta personal de confianza. No te protege del malware que ya se ejecuta con tu usuario.
- La cubierta predeterminada tapa las pantallas físicas mientras trabaja el agente. Las capturas no la incluyen y el agente puede seguir manejando las apps que hay debajo.
- El helper usa el hardened runtime y solo escucha en un socket local privado, nunca en la red.
- La clave de firma no se puede exportar y ninguna app tiene permiso previo para usarla. Hacer clic en **Always Allow** cambiaría eso.
- Nunca pegues tu contraseña de inicio de sesión en un chat, en un argumento de comando ni en una variable de entorno. Escríbela solo en el aviso oculto de setup.

Informa de vulnerabilidades de forma privada mediante los avisos de seguridad (security advisories) de GitHub.

## Desinstalar

```sh
sparekey uninstall
```

Elimina la credencial guardada, el helper, el LaunchAgent, los archivos de ejecución y los archivos de skill que escribió Sparekey. No elimina:

- la identidad `sparekey local signing` (bórrala en Acceso a Llaveros si quieres);
- la entrada de Accessibility (quítala en Ajustes del Sistema);
- el enlace `~/.local/bin/sparekey`.

## Créditos

La forma de interactuar con la pantalla de bloqueo se inspiró en [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift) de Cindy (Apache-2.0). Sparekey es una implementación independiente.

## Licencia

[MIT](LICENSE) © yoonpooh
