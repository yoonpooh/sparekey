<p align="center">
  <img src="docs/assets/logo.png" alt="Sparekey logo" width="160">
</p>

<h1 align="center">Sparekey</h1>

<p align="center">
  <strong>Una llave de repuesto para tu Mac, al servicio de tu agente de IA.</strong><br>
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

---

Los agentes que usan el ordenador o el navegador se detienen en cuanto se bloquea tu Mac. Sparekey es una pequeña CLI para macOS que permite a un agente desbloquear **tu propia sesión, en la que ya has iniciado sesión**, con una contraseña guardada localmente, terminar su tarea y volver a bloquearla.

```sh
sparekey unlock   # let the agent get to work; cover the physical displays
sparekey lock     # restore the lock when it is done
```

Con la skill de agente incluida, no tienes que indicar estos pasos. Pídele una tarea de GUI normal en un Mac bloqueado y el agente comprobará el estado, lo desbloqueará, hará el trabajo y volverá a bloquear la pantalla por sí mismo.

## Novedades de la versión 0.2.0

Inspirado en Locked Computer Use de Codex, Sparekey ahora cubre las pantallas físicas mientras trabaja un agente. La cubierta negra muestra el logotipo de Sparekey, el mensaje «Your agent is using this Mac» y un botón **Lock Mac**, para que nadie cercano pueda ver el trabajo del agente.

<p align="center">
  <img src="docs/assets/cover.png" alt="Cubierta de pantalla de Sparekey en un Mac" width="720">
</p>

- La cubierta se coloca debajo de la pantalla de bloqueo **antes** de enviar la contraseña, así que el escritorio nunca queda visible ni por un instante. No aparece en las capturas ni en las grabaciones de pantalla; el agente sigue viendo la pantalla real y sus clics y pulsaciones pasan a través de ella. Un clic en **Lock Mac** bloquea el Mac. Usa `sparekey unlock --no-cover` para omitirla; `sparekey lock` o cualquier otro bloqueo la retira. La cubierta oculta la pantalla, pero no bloquea el Mac.
- Si la pantalla bloqueada permanece encendida y muestra el fondo y el reloj en lugar de la cuenta, Sparekey hace que la pantalla entre en reposo y se reactive una vez para recuperar la cuenta. Sigue sin escribir nunca en una pantalla que no haya verificado.
- Después de `brew upgrade sparekey`, vuelve a ejecutar `sparekey setup`. Hasta entonces, la nueva CLI informa de `helper_version_mismatch`.

> **Estado:** fase temprana (0.2.0). Funciona en macOS 27.2 con Apple silicon: en dos ejecuciones sin instrucciones adicionales, el agente desbloqueó el Mac, trabajó y volvió a bloquearlo. No se han probado otras versiones de macOS. Depende de la disposición de Accessibility en la pantalla de bloqueo, no de una API pública de desbloqueo.

## Lo que no hace

Sparekey no sirve para eludir contraseñas, recuperar cuentas ni ofrecer acceso remoto. No puede desbloquear FileVault durante el arranque, una sesión cerrada, la cuenta de otra persona ni un Mac en reposo al que no se pueda acceder.

## Cómo funciona

```text
agent ──▶ sparekey CLI ──(private Unix socket, same-user check)──▶ helper (LaunchAgent)
                                                                     │
                     verifies console user, Apple-signed loginwindow,│
                     your account, and a single secure password field│
                                                                     ▼
                         login Keychain ──▶ one submission ──▶ state check
```

- `setup` copia el binario a una ubicación fija, lo firma con una identidad local de firma de código y lo ejecuta como helper en segundo plano para tu usuario.
- La contraseña se guarda en tu Keychain de inicio de sesión. Solo ese helper firmado puede leerla.
- El helper rellena únicamente un campo de contraseña verificado, envía la contraseña **como máximo una vez** y se detiene de forma segura ante cualquier imprevisto: otras cuentas, cuadros de diálogo, pantallas de recuperación o cambios en la interfaz.
- Un límite persistente de 30 segundos y un interruptor de seguridad evitan que una contraseña antigua acumule intentos fallidos de inicio de sesión.

## Requisitos

- macOS 13 o posterior, con una sesión de escritorio iniciada
- Xcode Command Line Tools con Swift 5.9 o posterior
- Una terminal local en el Mac para la configuración inicial

No hace falta una cuenta de Apple Developer.

## Instalación

Con Homebrew (compila el código fuente en tu Mac):

```sh
brew install yoonpooh/tap/sparekey
sparekey setup --skill codex   # or: --skill claude, --skill claude,codex, --no-skill
```

O compílalo tú mismo:

```sh
git clone https://github.com/yoonpooh/sparekey.git
cd sparekey
swift build -c release
.build/release/sparekey setup --skill codex
```

Ejecuta setup en una terminal local, con el Mac desbloqueado, no por SSH. El proceso:

1. Crea la identidad `sparekey local signing` en tu Keychain de inicio de sesión (solo la primera vez).
2. Firma e instala el helper en `~/Library/Application Support/sparekey/bin/sparekey`.
   - Cuando macOS pida permiso para usar la clave de firma, haz clic en **Allow**, no en **Always Allow**.
3. Solicita dos veces tu contraseña de inicio de sesión. La entrada permanece oculta y se comprueba con macOS.
   - Nunca la pegues en un chat, un argumento de comando ni una variable de entorno.
4. Inicia el helper en segundo plano e instala la skill de agente elegida.
5. Te ayuda a activar **Accessibility** para el helper. Abre los ajustes, muestra el archivo en Finder y copia su ruta; después vuelve a comprobar el permiso.

Si lo compilaste desde el código fuente, añade `sparekey` a tu `PATH`:

```sh
ln -s "$HOME/Library/Application Support/sparekey/bin/sparekey" ~/.local/bin/sparekey
sparekey doctor
```

Después de `brew upgrade sparekey` o de volver a compilar, ejecuta `sparekey setup` otra vez. Actualiza el helper firmado sin pedir la contraseña, salvo que el helper ya no pueda leerla.

## Skills de agente

setup puede instalar una skill para **Codex** (`~/.agents/skills/sparekey`) y **Claude Code** (`~/.claude/skills/sparekey`). También puedes instalarla más tarde:

```sh
sparekey skill install --agent codex
```

La skill indica al agente que:

- compruebe el bloqueo antes de trabajar con la GUI, o en cuanto falle el acceso a una aplicación o ventana;
- desbloquee una sola vez, confirme el resultado y haga la tarea;
- vuelva a bloquear al terminar, incluso si la tarea falla, pero solo si fue el propio agente quien desbloqueó el Mac;
- se detenga y comunique los errores en lugar de reintentar.

Pedir una tarea de GUI cuenta como permiso para desbloquear el Mac durante esa tarea. Indica al agente si quieres que el Mac quede bloqueado o desbloqueado al terminar.

## Comandos

| Comando | Función |
| --- | --- |
| `sparekey unlock [--no-cover]` | Desbloquea una vez y confirma el estado; por defecto cubre las pantallas físicas y mantiene la pantalla activa hasta ejecutar `lock` o durante 60 minutos. |
| `sparekey lock` | Bloquea y confirma; si ya está bloqueado, no hace nada. |
| `sparekey status` | Muestra `locked` o `unlocked`. |
| `sparekey probe` | Activa la pantalla y comprueba el campo de contraseña sin leerla. |
| `sparekey setup` | Instala o actualiza el helper, la credencial y las skills. |
| `sparekey doctor` | Comprueba la instalación, la firma, el helper, Accessibility, la credencial y las skills. |
| `sparekey skill install` | Instala la skill de agente. |
| `sparekey uninstall` | Elimina el helper, la credencial, LaunchAgent y las skills escritas por Sparekey. |

Si ejecutas `sparekey` sin argumentos, muestra la ayuda; nunca desbloquea.

<details>
<summary><strong>Salida JSON, códigos de salida y códigos de error</strong></summary>

`unlock`, `lock`, `status`, `probe` y `doctor` aceptan `--json`:

```json
{"ok":true,"command":"status","state":"locked","message":"locked"}
{"ok":false,"command":"unlock","error":{"code":"rate_limited","message":"..."}}
```

Códigos de salida: `0` para éxito, `1` para fallo operativo y `2` para error de uso. Una ejecución correcta de `status` puede indicar cualquiera de los dos estados; consulta `state`.

Códigos de error: `usage`, `not_set_up`, `helper_not_running`, `helper_version_mismatch`, `no_console_session`, `accessibility_missing`, `credential_unavailable`, `login_window_unsupported`, `field_not_ready`, `cover_unavailable`, `rate_limited`, `breaker_tripped`, `unlock_not_confirmed`, `lock_not_confirmed`, `internal`. `doctor --json` también puede indicar `skill_outdated` y añade el mapa `statuses` por comprobación (`ok`, `warn`, `fail`, `skip`).

</details>

## Solución de problemas

Empieza con `sparekey doctor`. Cada comprobación fallida indica cómo resolverla.

- **Falta Accessibility:** habilita `~/Library/Application Support/sparekey/bin/sparekey` en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Si acabas de habilitarlo, ejecuta `setup` de nuevo o reinicia el helper con `launchctl kickstart -k "gui/$(id -u)/io.github.yoonpooh.sparekey.helper"`.
- **`breaker_tripped` o `unlock_not_confirmed`:** la contraseña guardada podría ser incorrecta, por ejemplo, si la cambiaste. Ejecuta `sparekey setup --reset-password` localmente.
- **`credential_unavailable` después de actualizar:** vuelve a ejecutar `sparekey setup` e introduce la contraseña cuando se te pida.
- **`rate_limited`:** hubo un intento en los últimos 30 segundos. No insistas en bucle.

## Seguridad

Lee [SECURITY.md](SECURITY.md) antes de instalarlo. En resumen:

- **Cualquier proceso que se ejecute con tu usuario puede pedirle al helper que desbloquee el Mac.** Sparekey está pensado para una cuenta personal de confianza. No te protege frente a malware que ya se ejecute con tu usuario.
- La cubierta predeterminada oculta las pantallas físicas mientras trabaja el agente. No aparece en las capturas y el agente puede seguir manejando las aplicaciones situadas debajo.
- El helper usa el entorno de ejecución reforzado y solo escucha en un socket local privado, nunca en la red.
- La clave de firma no se puede exportar y ninguna aplicación tiene permiso previo para usarla. Hacer clic en **Always Allow** cambiaría eso.

Comunica las vulnerabilidades de forma privada mediante los avisos de seguridad de GitHub.

## Desinstalación

```sh
sparekey uninstall
```

Se eliminan la credencial guardada, el helper, LaunchAgent, los archivos de ejecución y los archivos de skill escritos por Sparekey. No se eliminan:

- la identidad `sparekey local signing` (puedes borrarla en Keychain Access);
- la entrada de Accessibility (puedes quitarla en Ajustes del Sistema);
- el enlace `~/.local/bin/sparekey`.

## Créditos

El método de interacción con la pantalla de bloqueo se inspiró en [MacScreenUnlock.swift](https://github.com/makecindy/cindy/blob/main/packages/remote-credentials-native/Sources/CindyRemoteCredentials/MacScreenUnlock.swift), de Cindy (Apache-2.0). Sparekey es una implementación independiente. Las notas de diseño están en [docs/DESIGN.md](docs/DESIGN.md).

## Licencia

[MIT](LICENSE) © yoonpooh
