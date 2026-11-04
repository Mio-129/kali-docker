# kali-docker

GitHub Codespaces açıldığında **Docker komutlarıyla Kali Linux'u otomatik kuran** repo.
Buna ek olarak **Kali XFCE masaüstü noVNC ile Codespace'in `6080` portunda tarayıcıda açılır** —
yani Docker Desktop benzeri bir panel değil, gerçek bir Linux masaüstü ekranı görürsün.

> Beta / eğitim amaçlı. Kali araçlarını yalnızca izniniz olan sistemlerde kullanın.

## Ekran Codespace portunda çıkıyor mu? Evet

Codespace açıldığında `6080` portu otomatik forward edilir ve VS Code'da **preview sekmesi
olarak açılır** (`onAutoForward: openPreview`). Adres:

```
https://<codespace-adi>-6080.app.github.dev/vnc.html
```

Kurulum bittiğinde terminalde de tam URL yazdırılır. `/` adresi otomatik olarak
`vnc.html?autoconnect=true&resize=scale`'e yönlendirir; noVNC şifre sorarsa **`kali`** girin
(`KALI_VNC_PASSWORD` ile değiştirilebilir). İstersen `5901` portunu bir VNC istemcisiyle de
kullanabilirsin.

| Port | Servis | Erişim |
| --- | --- | --- |
| `6080` | Kali masaüstü (noVNC / XFCE) | Tarayıcı, `forwardPorts` ile otomatik açılır |
| `5901` | Ham VNC | VNC istemcisi (opsiyonel) |
| `9443` | Portainer — Docker web paneli | Sadece `KALI_PORTAINER=1` ise |

Masaüstü; Xvfb sanal ekranı, `startxfce4`, `x11vnc` ve `websockify`/noVNC ile çalışır. Hepsi
Kali konteynerinin içinde, `Dockerfile`'ın `desktop` hedefinde kurulur.

## Codespace açınca ne olur?

`.devcontainer/devcontainer.json` varsayılan yapılandırmadır:

1. Codespace, Docker-in-Docker özelliğiyle açılır (`docker` komutu çalışır).
2. `postCreateCommand` → `bash .devcontainer/setup-kali.sh` otomatik çalışır ve sırayla:
   - `docker pull kalilinux/kali-rolling`
   - `docker build -t kali-docker:local .` (terminal imajı, `cli` hedefi)
   - `docker build --target desktop -t kali-docker:desktop .` (XFCE + noVNC imajı)
   - `docker run -d --name kali -p 6080:6080 -p 5901:5901 ... kali-docker:desktop`
     (repo `/workspace` olarak bağlanır)
   - `kali` kısayol komutu kurulur, `6080` portunun hazır olması beklenir
3. `postStartCommand`, Codespace her yeniden başladığında konteyneri tekrar ayağa kaldırır
   (idempotent; varsa yeniden oluşturmaz).

**Kullanım:**

```bash
kali                              # etkileşimli Kali bash (aynı konteyner)
kali nmap -sV 192.168.1.1        # tek komut çalıştırma
docker exec -it kali bash         # doğrudan docker ile aynı işlem
docker logs kali                  # masaüstü/Xvfb kayıtları
docker ps                         # çalışan konteynerler
```

Terminal profili olarak **Kali Linux** da seçilebilir (VS Code → Terminal profili).

### Sadece terminal istiyorsan

`KALI_DESKTOP=0` ortam değişkeniyle masaüstü kapatılır; XFCE imajı build edilmez, konteyner
`kali-docker:local` ile `tail -f /dev/null` olarak çalışır. Mevcut konteyner imajı farklıysa
script onu otomatik olarak yeniden oluşturur.

### Docker Desktop benzeri panel

`KALI_PORTAINER=1` ile Docker konteyner/imajlarını gösteren bir web paneli de açılır:
`https://<codespace-adi>-9443.app.github.dev` (Portainer, ilk girişte admin şifresi oluşturulur).

## Alternatif: Codespace'in kendisi Kali olsun

`Kali Linux (dogrudan, Docker'siz)` yapılandırması (`.devcontainer/kali/devcontainer.json`)
Codespace'i doğrudan `Dockerfile`'ın `cli` hedefinden kurar; iç içe Docker ve noVNC masaüstü
olmaz — terminalin kendisi Kali'dir. Codespace oluştururken "Dev container configuration"
seçeneğinden bunu seçin.

## Yerel kullanım (Codespace olmadan)

```bash
# Terminal imajı
docker build -t kali-docker .
docker run --rm -it -v "$PWD:/workspace" kali-docker bash

# Masaüstü imajı -> http://localhost:6080/vnc.html  (şifre: kali)
docker build --target desktop -t kali-docker:desktop .
docker run --rm -p 6080:6080 -p 5901:5901 \
    -e KALI_VNC_PASSWORD=kali -e KALI_VNC_RESOLUTION=1920x1080x24 \
    kali-docker:desktop

# Daha fazla araçla (her iki hedefe de uygulanır):
docker build --build-arg KALI_PACKAGES="kali-linux-headless" -t kali-docker:full .
```

`Dockerfile`'ın `cli` hedefi varsayılan olarak hafif bir araç seti kurar (`nmap`, `hydra`,
`john`, `sqlmap`, `nikto`, `dirb`, `tcpdump`, `netcat`, `python3` ...); `desktop` hedefi bunun
üzerine masaüstü paketlerini ekler. CI/GHCR build'leri her zaman hafif `cli` hedefini kullanır.

## Özelleştirme

| Değişken | Yer | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `KALI_DESKTOP` | Codespace env | `1` | `0` = masaüstü yok, sadece terminal |
| `KALI_WEB_PORT` | Codespace env | `6080` | noVNC host portu |
| `KALI_VNC_PORT` | Codespace env | `5901` | VNC host portu |
| `KALI_VNC_PASSWORD` | Codespace env | `kali` | noVNC/VNC şifresi (VNC en fazla 8 karakter) |
| `KALI_VNC_RESOLUTION` | Codespace env | `1280x800x24` | Sanal ekran çözünürlüğü |
| `KALI_PORTAINER` | Codespace env | `0` | `1` = Portainer web paneli |
| `KALI_PORTAINER_PORT` | Codespace env | `9443` | Portainer host portu |
| `KALI_IMAGE` | Codespace env | `kali-docker:local` | Terminal imajı |
| `KALI_DESKTOP_IMAGE` | Codespace env | `kali-docker:desktop` | Masaüstü imajı |
| `KALI_CONTAINER` | Codespace env | `kali` | Konteyner adı |
| `KALI_WORKSPACE` | Codespace env | repo kökü | Konteynere bağlanan dizin |
| `KALI_DOCKER_WAIT_ATTEMPTS` | Codespace env | `45` (~90 sn) | Docker daemon deneme sayısı |
| `KALI_DESKTOP_WAIT_ATTEMPTS` | Codespace env | `30` (~30 sn) | noVNC'nin açılmasını bekleme süresi |
| `KALI_PACKAGES` | `docker build --build-arg` | hafif araç seti | Kurulacak Kali paketleri |

Port / şifre / çözünürlük değişiklikleri **var olan konteynere** uygulanmaz. Önce
`docker rm -f kali` ile silip script'i yeniden çalıştır. Portları değiştirirsen
`.devcontainer/devcontainer.json`'daki `forwardPorts` değerlerini de güncelle.

```bash
bash .devcontainer/setup-kali.sh               # imajları yeniden kur + konteyneri başlat
bash .devcontainer/setup-kali.sh --start-only  # sadece konteyneri başlat
```

## GitHub Actions workflow'ları

| Workflow | Ne yapar |
| --- | --- |
| `docker-image.yml` | `push` / `pull_request` / manuel: JSON config + shell script doğrular, `cli` imajını build eder |
| `docker-publish.yml` | Günlük / `main` push / `v*` etiketleri: imajı `ghcr.io/<owner>/<repo>` adresine push eder ve cosign ile imzalar |

## Güvenlik notları

- Codespace port forwarding varsayılan olarak **private**'tır (GitHub hesabıyla doğrulama ister).
  `6080`/`5901` portlarını public yapmayın; yapmanız gerekirse güçlü bir `KALI_VNC_PASSWORD` koyun.
- Docker-in-Docker özelliği Codespace konteynerini `--privileged` çalıştırır; iç içe Docker
  istemiyorsanız "dogrudan" yapılandırmayı tercih edin.
- Masaüstü oturumu `root` olarak çalışır; yalnızca izinli hedeflerde test yapın.
