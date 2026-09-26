{
  coreutils,
  winePrefix ? null,
  grabPointer ? null,
  extraEnvironment ? { },
  fetchurl,
  icoutils,
  lib,
  makeDesktopItem,
  proton-ge-bin,
  protonPackage ? proton-ge-bin,
  runCommand,
  symlinkJoin,
  umu-launcher,
  writeShellApplication,
}:

let
  pname = "eve-online";
  version = "1.16.1";
  reservedEnvironmentNames = [
    "WINEPREFIX"
    "EVE_WINEPREFIX"
    "EVE_GRAB_POINTER"
    "STEAM_COMPAT_INSTALL_PATH"
    "PROTONPATH"
  ];
  validEnvironmentName =
    name:
    builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null
    && !(builtins.elem name reservedEnvironmentNames);
  defaultEnvironment = {
    GAMEID = "umu-default";
    STORE = "none";
    UMU_CONTAINER_NSENTER = "1";
    PROTONFIXES_DISABLE = "1";
    PROTON_USE_XALIA = "0";
  };
  # Explicit package defaults opt these variables into runtime overrides.
  environmentToClear = builtins.filter (name: !(builtins.hasAttr name extraEnvironment)) [
    "PROTON_VERB"
    "STEAM_COMPAT_LAUNCHER_SERVICE"
    "UMU_CONTAINER_NSENTER"
    "UMU_CONTAINER_NSENTER_CREATE"
    "UMU_CONTAINER_NSENTER_REQUIRED"
  ];
  environmentExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value:
      if builtins.hasAttr name extraEnvironment then
        ''
          if [[ ! -v ${name} ]]; then
            export ${name}=${lib.escapeShellArg value}
          fi
        ''
      else
        "export ${name}=${lib.escapeShellArg value}"
    ) (defaultEnvironment // extraEnvironment)
  );

  installer = fetchurl {
    url = "https://launcher.ccpgames.com/eve-online/release/win32/x64/eve-online-${version}+Setup.exe";
    name = "eve-online-${version}+Setup.exe";
    hash = "sha256-feTzI01T8nYVoBJviwIvrLZooitEYzNP/jcNk5LgLOc=";
  };

  launcherIcon = runCommand "${pname}-icon-${version}" { nativeBuildInputs = [ icoutils ]; } ''
    iconPath="$out/share/icons/hicolor/256x256/apps/${pname}.png"
    mkdir -p "$(dirname "$iconPath")"
    wrestool --extract --raw --type=3 --name=19 --output="$iconPath" ${lib.escapeShellArg installer}
  '';

  launcher = writeShellApplication {
    name = pname;
    runtimeInputs = [
      coreutils
      umu-launcher
    ];
    text = ''
      umask 077

      show_help() {
        cat <<'EOF'
      Usage: eve-online [--install | --help] [launcher arguments...]

        (default)  Run CCP's official EVE Online launcher
        --install  Run the packaged CCP launcher installer
        --help     Show this help

      Environment:
        EVE_WINEPREFIX    Absolute path to override the configured Wine prefix
        PROTONPATH        Override the configured Proton installation
        EVE_LAUNCHER_EXE  Absolute path to the launcher executable
        EVE_GRAB_POINTER  Y/N to set Wine's GrabPointer; empty leaves it unchanged
      EOF
        ${
          if winePrefix == null then
            ''printf '  Default prefix: %s/Games/eve-online\n' "$HOME"''
          else
            ''printf '  Default prefix: %s\n' ${lib.escapeShellArg winePrefix}''
        }
        cat <<'EOF'

      Close the launcher and all EVE clients before running --install.
      EOF
      }

      if [[ "''${1:-}" == --help || "''${1:-}" == -h ]]; then
        show_help
        exit 0
      fi

      grab_pointer=${
        lib.escapeShellArg (
          if grabPointer == null then
            ""
          else if grabPointer then
            "Y"
          else
            "N"
        )
      }
      if [[ -v EVE_GRAB_POINTER ]]; then
        grab_pointer="$EVE_GRAB_POINTER"
      fi
      case "$grab_pointer" in
        ""|Y|N) ;;
        *)
          printf 'EVE_GRAB_POINTER must be Y, N, or empty: %s\n' "$grab_pointer" >&2
          exit 2
          ;;
      esac

      if [[ -n "''${EVE_WINEPREFIX:-}" ]]; then
        if [[ "$EVE_WINEPREFIX" != /* ]]; then
          printf 'EVE_WINEPREFIX must be an absolute path: %s\n' "$EVE_WINEPREFIX" >&2
          exit 2
        fi
        WINEPREFIX="$EVE_WINEPREFIX"
      else
        WINEPREFIX=${
          if winePrefix == null then ''"$HOME/Games/eve-online"'' else lib.escapeShellArg winePrefix
        }
      fi
      WINEPREFIX="$(realpath -m -- "$WINEPREFIX")"
      export WINEPREFIX
      export STEAM_COMPAT_INSTALL_PATH="$WINEPREFIX"

      # Clear inherited launch settings unless explicitly configured through
      # extraEnvironment, so UMU can choose the verb and reuse this prefix's container.
      ${lib.optionalString (
        environmentToClear != [ ]
      ) "unset ${lib.concatStringsSep " " environmentToClear}"}
      if [[ -z "''${PROTONPATH:-}" ]]; then
        export PROTONPATH=${lib.escapeShellArg protonPackage.steamcompattool}
      fi
      ${lib.optionalString (!(extraEnvironment ? WINEDLLOVERRIDES)) ''
        export WINEDLLOVERRIDES="winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      ''}
      ${environmentExports}

      query_registry() {
        # Proton logging redirects reg.exe's output to a file. Disable it only
        # for queries whose output we parse, preserving logging for the app.
        PROTON_LOG=0 PROTON_VERB=run umu-run 'C:\windows\system32\reg.exe' query "$@"
      }

      read_dotnet_registration() {
        local status=0
        # UMU can return success even when reg.exe reports a missing key,
        # so inspect the returned values as well as the process status.
        dotnet_registration="$(query_registry "$@")" || status=$?
        if (( status > 1 )); then
          printf 'Unable to check the .NET Framework registration in %s\n' "$WINEPREFIX" >&2
          exit "$status"
        fi
      }

      has_dotnet_runtime() {
        local release_pattern='Release[[:space:]]+REG_DWORD[[:space:]]+0x([[:xdigit:]]{1,8})([[:space:]]|$)'
        # 379893 is .NET Framework 4.5.2, required by the CCP installer.
        [[ "$dotnet_registration" =~ $release_pattern ]] && (( 16#''${BASH_REMATCH[1]} >= 379893 ))
      }

      ensure_dotnet_runtime() {
        local mono_msi view dotnet_registration
        local dotnet_key='HKLM\Software\Microsoft\NET Framework Setup\NDP\v4'
        local mono_installers=()
        # The packaged Squirrel installer is 32-bit and requires the Full profile.
        read_dotnet_registration "$dotnet_key\Full" /reg:32
        if has_dotnet_runtime; then
          return
        fi

        for view in 32 64; do
          # Do not install Mono over an existing native .NET installation,
          # including Client-only and 64-bit-only registrations.
          read_dotnet_registration "$dotnet_key" "/reg:$view"
          if [[ "$dotnet_registration" == *'HKEY_LOCAL_MACHINE\Software\Microsoft\NET Framework Setup\NDP\v4'* ]]; then
            printf '%s\n' \
              'The existing .NET Framework registration is older than 4.5.2 or incomplete.' \
              'Repair that runtime or use a fresh EVE_WINEPREFIX before running --install.' >&2
            exit 1
          fi
        done

        # Use Mono from the selected Proton, including a PROTONPATH override.
        # Some Proton releases bundle it without registering it in default_pfx.
        shopt -s nullglob
        mono_installers=( "$PROTONPATH"/{files,dist}/share/wine/mono/wine-mono*/support/winemono-support.msi )
        shopt -u nullglob
        if (( ''${#mono_installers[@]} == 0 )); then
          printf 'Wine Mono support installer not found in Proton installation: %s\n' "$PROTONPATH" >&2
          exit 1
        fi
        mono_msi="$(printf '%s\n' "''${mono_installers[@]}" | sort --version-sort | tail -n 1)"
        mono_msi="$(realpath -e -- "$mono_msi")"
        printf 'Installing bundled Wine Mono support in %s\n' "$WINEPREFIX"
        PROTON_VERB=run umu-run 'C:\windows\system32\msiexec.exe' \
          /i "Z:''${mono_msi//\//\\}" /qn /norestart

        read_dotnet_registration "$dotnet_key\Full" /reg:32
        if ! has_dotnet_runtime; then
          printf 'Wine Mono did not register .NET Framework support in %s\n' "$WINEPREFIX" >&2
          exit 1
        fi
      }

      configure_grab_pointer() {
        if [[ -n "$grab_pointer" ]]; then
          local registration
          local value_pattern="GrabPointer[[:space:]]+REG_SZ[[:space:]]+$grab_pointer([[:space:]]|$)"
          # Use the selected Proton through UMU. The run verb avoids waiting
          # for other Wine processes to exit before updating the registry.
          PROTON_VERB=run umu-run 'C:\windows\system32\reg.exe' add \
            'HKCU\Software\Wine\X11 Driver' \
            /v GrabPointer /t REG_SZ /d "$grab_pointer" /f

          # Check the stored value because UMU can mask reg.exe failures.
          if ! registration="$(query_registry 'HKCU\Software\Wine\X11 Driver' /v GrabPointer)" \
            || [[ ! "$registration" =~ $value_pattern ]]; then
            printf 'Unable to set GrabPointer=%s in %s\n' "$grab_pointer" "$WINEPREFIX" >&2
            exit 1
          fi
        fi
      }

      discover_launcher() {
        local root root_exe version_exe latest_versioned
        local launcher_roots=()
        local version_candidates=()
        local active_versions=()

        if [[ -n "''${EVE_LAUNCHER_EXE:-}" ]]; then
          if [[ "$EVE_LAUNCHER_EXE" != /* || ! -f "$EVE_LAUNCHER_EXE" ]]; then
            printf 'EVE_LAUNCHER_EXE must be an absolute path to an existing file: %s\n' \
              "$EVE_LAUNCHER_EXE" >&2
            return 2
          fi

          launcher_exe="$(realpath -e -- "$EVE_LAUNCHER_EXE")" || return 2
          launcher_workdir="$(dirname "$launcher_exe")"
          return 0
        fi

        shopt -s nullglob
        launcher_roots=(
          "$WINEPREFIX"/drive_c/users/steamuser/AppData/Local/eve-online
          "$WINEPREFIX"/drive_c/users/*/AppData/Local/eve-online
        )
        shopt -u nullglob

        for root in "''${launcher_roots[@]}"; do
          [[ -d "$root" ]] || continue
          root_exe="$root/eve-online.exe"
          active_versions=()

          shopt -s nullglob
          version_candidates=( "$root"/app-[0-9]*/eve-online.exe )
          shopt -u nullglob

          for version_exe in "''${version_candidates[@]}"; do
            if [[ -f "$version_exe" && ! -e "$(dirname "$version_exe")/.dead" ]]; then
              active_versions+=( "$version_exe" )
            fi
          done

          if (( ''${#active_versions[@]} > 0 )); then
            latest_versioned="$(
              printf '%s\n' "''${active_versions[@]}" \
                | sort --version-sort \
                | tail -n 1
            )"
            launcher_workdir="$(dirname "$latest_versioned")"
            if [[ -f "$root_exe" ]]; then
              launcher_exe="$root_exe"
            else
              launcher_exe="$latest_versioned"
            fi
            return 0
          fi

          if [[ -f "$root_exe" ]]; then
            launcher_workdir="$root"
            launcher_exe="$root_exe"
            return 0
          fi
        done

        return 1
      }

      case "''${1:-}" in
        --install)
          shift
          mkdir -p "$WINEPREFIX"
          cd "$WINEPREFIX"
          ensure_dotnet_runtime
          configure_grab_pointer
          exec umu-run ${lib.escapeShellArg installer} "$@"
          ;;
        *)
          if discover_launcher; then
            cd "$launcher_workdir"
            configure_grab_pointer
            exec umu-run "$launcher_exe" --product=eve-online "$@"
          else
            discovery_status=$?
            if (( discovery_status == 1 )); then
              printf 'CCP launcher not found in Wine prefix: %s\n' "$WINEPREFIX" >&2
              printf '%s\n' \
                'Run eve-online --install or set EVE_LAUNCHER_EXE to its absolute path.' >&2
            fi
            exit "$discovery_status"
          fi
          ;;
      esac
    '';
  };

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "EVE Online";
    genericName = "EVE Online Launcher";
    comment = "EVE Online launcher";
    exec = "${launcher}/bin/${pname}";
    icon = pname;
    categories = [ "Game" ];
    startupNotify = true;
  };
in
assert lib.assertMsg (
  protonPackage ? steamcompattool
) "protonPackage must provide a steamcompattool path";
assert lib.assertMsg (
  winePrefix == null || lib.hasPrefix "/" winePrefix
) "winePrefix must be an absolute path";
assert lib.assertMsg (
  grabPointer == null || builtins.isBool grabPointer
) "grabPointer must be null or a boolean";
assert lib.assertMsg (builtins.all validEnvironmentName (builtins.attrNames extraEnvironment))
  "extraEnvironment needs valid shell variable names; use dedicated overrides for reserved variables";
assert lib.assertMsg (builtins.all builtins.isString (
  builtins.attrValues extraEnvironment
)) "extraEnvironment values must be strings";
symlinkJoin {
  inherit pname version;
  paths = [
    launcher
    launcherIcon
    desktopItem
  ];

  meta = {
    description = "EVE Online launcher using UMU and Proton";
    homepage = "https://www.eveonline.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
