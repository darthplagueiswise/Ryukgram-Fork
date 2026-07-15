#!/bin/sh
# sync_438.sh — aplica as mudanças da revisão 438 no repo local do iSH e sobe pro GitHub.
# Uso (no iSH, com este zip salvo em /root/):
#   cd /root && unzip -o RyukGram_438.zip -d RyukGram_438 && sh RyukGram_438/sync_438.sh
set -e
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="/root/Ryukgram-Fork-experiments2"
BRANCH="experiments2"

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "ERRO: $REPO_DIR não é um repo git. Ajuste REPO_DIR no topo do script."
    exit 1
fi

echo "==> Atualizando repo local a partir do remote..."
cd "$REPO_DIR"
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH" || echo "  (pull com avisos — seguindo)"

echo "==> Identidade git..."
if [ -z "$(git config user.email)" ]; then
    printf "  Nome pro commit [darthplagueiswise]: "; read GN; GN="${GN:-darthplagueiswise}"
    printf "  Seu e-mail (mesmo da conta GitHub): "; read GE
    while [ -z "$GE" ]; do printf "  E-mail não pode ficar vazio: "; read GE; done
    git config user.name "$GN"; git config user.email "$GE"
fi

echo "==> Copiando arquivos novos/modificados da 438..."
cd "$BUNDLE_DIR"
find . -type f ! -name 'sync_438.sh' ! -name 'DELETIONS.txt' ! -name 'PATCH_438.diff' | while IFS= read -r f; do
    rel="${f#./}"
    dest="$REPO_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
    echo "  + $rel"
done

cd "$REPO_DIR"
echo "==> Status:"
git status --short
git add -A
if git diff --cached --quiet; then
    echo "  Nada novo pra commitar (já estava atualizado)."
else
    if ! git commit -m "SCI 438: migração MobileConfig + SCIExperimentForce + revalidação completa (438)"; then
        echo "ERRO: commit falhou. Nada foi enviado."; exit 1
    fi
    if ! git push origin "$BRANCH"; then
        echo "ERRO: push falhou. O commit ficou local — rode 'git push origin $BRANCH' depois de resolver."; exit 1
    fi
    echo "  Commit e push OK."
fi
echo "==> Pronto. Local ($REPO_DIR) e remote (origin/$BRANCH) atualizados pra 438."
