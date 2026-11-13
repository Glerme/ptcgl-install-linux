# Login do PTCGL no Linux: enviar o callback na mão (Linux Mint)

O login do jogo devolve o resultado por um link `tpcitcgapp://callback?code=...`.
No Windows, uma segunda cópia do jogo abre, encontra a primeira e passa o código para ela.
No Wine isso só funciona se a segunda cópia usar **o mesmo wineserver** do jogo aberto,
ou seja, o mesmo Wine/Proton, o mesmo prefixo e, no Flatpak, o mesmo sandbox.
Steam, Heroic e Lutris sobem um Proton novo no host, então abre uma segunda janela e o login não acontece.

A solução é rodar você mesmo a segunda cópia dentro do ambiente do jogo que já está aberto.

## 1. Pegar a URL do callback

1. Abra o jogo e clique em **Login**. Deixe o jogo aberto nessa tela o tempo todo.
2. No navegador, aperte **F12** e abra a aba **Console** *antes* de fazer login.
3. Faça login. O redirecionamento falha e o console mostra algo como
   `Failed to launch 'tpcitcgapp://callback?code=...'`.
   A URL também aparece na aba **Network**.
4. Copie a URL inteira `tpcitcgapp://callback?code=...`. O código expira rápido, então faça o próximo passo logo em seguida.

## 2a. Heroic (Flatpak ou .deb) ou Lutris

Abra um terminal e cole o bloco abaixo. Coloque a sua URL entre as aspas simples da primeira linha:

```bash
URL='tpcitcgapp://callback?code=COLE_AQUI'

# O processo Wine do jogo: a linha de comando dele tem um caminho do Windows (C:\...)
pid=$(pgrep -of '[\\]Pokemon TCG Live[.]exe')
[ -n "$pid" ] || { echo "O jogo não está aberto"; }
wine="$(dirname "$(readlink /proc/$pid/exe)")/wine"
exe=$(tr '\0' '\n' < /proc/$pid/cmdline | grep -m1 -i 'Pokemon TCG Live.exe')
echo "pid=$pid  wine=$wine  exe=$exe"

if [ -e "/proc/$pid/root/.flatpak-info" ]; then
  # Heroic/Lutris em Flatpak: entra no sandbox do jogo (copia o ambiente do jogo)
  flatpak enter "$pid" "$wine" "$exe" "$URL"
else
  # Launcher nativo: copia o ambiente do jogo e roda o mesmo wine
  ( while IFS= read -rd '' v; do export "$v"; done < /proc/$pid/environ
    "$wine" "$exe" "$URL" )
fi
```

O jogo que já está aberto deve terminar o login, sem abrir uma segunda janela.

Observações:
- No Heroic, deixe o **UMU desligado** para o jogo. Com o UMU ligado, o jogo roda no container do Steam e esse bloco não consegue chegar nele.
- Se o `echo` mostrar o `pid` vazio, o jogo não está aberto ou o `.exe` tem outro nome. Confira com `pgrep -af 'TCG'`.
- Se o `flatpak enter` mostrar `Operation not permitted`, atualize o flatpak com `sudo apt update && sudo apt upgrade` e tente de novo.

## 2b. Steam (.deb nativo, jogo adicionado como Jogo Não-Steam com Proton)

No Steam o jogo roda dentro do container do Steam Linux Runtime, então é preciso pedir para esse container rodar o comando.

1. No Steam, clique com o botão direito no jogo e vá em **Propriedades → Opções de inicialização**. Coloque:
   ```
   STEAM_COMPAT_LAUNCHER_SERVICE=proton %command%
   ```
2. Abra o jogo e pegue a URL como no passo 1.
3. No terminal:
   ```bash
   URL='tpcitcgapp://callback?code=COLE_AQUI'
   LC=$(find ~/.steam/root/steamapps/common -name steam-runtime-launch-client -path '*sniper*' | head -1)
   pid=$(pgrep -of '[\\]Pokemon TCG Live[.]exe')
   exe=$(tr '\0' '\n' < /proc/$pid/cmdline | grep -m1 -i 'Pokemon TCG Live.exe')

   "$LC" --list          # mostra algo como --bus-name=com.steampowered.App1234567890
   "$LC" --bus-name=com.steampowered.AppXXXXXXXX --directory='' -- wine "$exe" "$URL"
   ```
   Troque `AppXXXXXXXX` pelo nome que o `--list` mostrou.

Se o `find` não mostrar nada, procure `SteamLinuxRuntime_sniper` em `~/.steam/root/steamapps/common` e instale pela Biblioteca do Steam (Ferramentas).

## Por que não fechar o jogo e abrir de novo com a URL?

O código pertence ao login que o jogo aberto começou. Uma cópia nova do jogo não consegue usar esse código,
então ele precisa ir para a janela que já está aberta.
