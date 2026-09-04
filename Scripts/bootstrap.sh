#!/usr/bin/env bash
# Genera GrabaAnalisis.xcodeproj a partir de project.yml.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen no esta instalado."
  echo "  brew install xcodegen"
  echo "  # o: mint install yonaskolb/XcodeGen"
  exit 1
fi

xcodegen generate
echo
echo "Listo. Abre el proyecto con:  open GrabaAnalisis.xcodeproj"
echo
echo "Antes de compilar en un dispositivo real:"
echo "  1. Selecciona tu equipo de firma en los tres targets."
echo "  2. Cambia com.grabaanalisis.* por tu propio prefijo de bundle id."
echo "  3. Registra el App Group group.com.grabaanalisis.shared en ambos targets."
