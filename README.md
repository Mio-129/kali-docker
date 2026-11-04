# kali-docker

GitHub Codespaces açıldığında **Docker komutlarıyla Kali Linux'u otomatik kuran** repo.
Depodaki `Dockerfile` hem GitHub Actions workflow'ları hem de Codespace tarafından kullanılır.

> Beta / eğitim amaçlı. Kali araçlarını yalnızca izniniz olan sistemlerde kullanın.

## Codespace açınca ne olur?

`.devcontainer/devcontainer.json` varsayılan yapılandırmadır:

1. Codespace, Docker-in-Docker özelliğiyle açılır (`docker` komutu çalışır).
2. `postCreateCommand` → `bash .devcontainer/setup-kali.sh` otomatik çalışır ve sırayla:
   - `docker pull kalilinux/kali-rolling`
   - `docker build -f Dockerfile -t kali-docker:local .`
   - `docker run -d --name kali ... kali-docker:local` (repo `/workspace` olarak bağlanır)
   - `kali` kısayol komutu kurulur
3. `postStartCommand`, Codespace her yeniden başladığında konteyneri tekrar ayağa kaldırır (idempotent; varsa yeniden oluşturmaz).

**Kullanım:** Codespace'te bir terminal açıp `kali` yazın → Kali kabuğuna girersiniz.

```bash
kali                              # etkileşimli Kali bash
kali nmap -sV 192.168.1.1        # tek komut çalıştırma
docker exec -it kali bash         # doğrudan docker ile aynı işlem
docker ps                         # çalışan konteynerler
docker logs kali                  # kurulum/konteyner kayıtları
```

Terminal profili olarak **Kali Linux** da seçilebilir (VS Code → Terminal profili).

### Alternatif: Codespace'in kendisi Kali olsun

`Kali Linux (dogrudan, Docker'siz)` yapılandırması (`.devcontainer/kali/devcontainer.json`)
Codespace'i doğrudan `Dockerfile`'dan kurar; iç içe Docker gerekmez. Codespace oluştururken
"Dev container configuration" seçeneğinden bunu seçin. Bu modda `docker` komutu olmadığı için
`kali` kısayolu da kullanılmaz — terminalin kendisi Kali'dir.

## Yerel kullanım (Codespace olmadan)

```bash
docker build -t kali-docker .
docker run --rm -it -v "$PWD:/workspace" kali-docker bash

# Daha fazla araçla:
docker build --build-arg KALI_PACKAGES="kali-linux-headless" -t kali-docker:full .
```

`Dockerfile` varsayılan olarak hafif bir araç seti kurar (`nmap`, `hydra`, `john`,
`sqlmap`, `nikto`, `dirb`, `tcpdump`, `netcat`, `python3` ...). `KALI_PACKAGES` argümanıyla
Kali metapaketleri de eklenebilir.

## Özelleştirme

| Değişken | Yer | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `KALI_IMAGE` | Codespace env | `kali-docker:local` | Yerel imaj etiketi |
| `KALI_CONTAINER` | Codespace env | `kali` | Konteyner adı |
| `KALI_WORKSPACE` | Codespace env | repo kökü | Konteynere bağlanan dizin |
| `KALI_DOCKER_WAIT_ATTEMPTS` | Codespace env | `45` (~90 sn) | Docker daemon için 2 saniyelik deneme sayısı |
| `KALI_PACKAGES` | `docker build --build-arg` | hafif araç seti | Kurulacak Kali paketleri |

Kurulumu elle tekrar çalıştırmak için:

```bash
bash .devcontainer/setup-kali.sh               # imajı yeniden kur + konteyneri başlat
bash .devcontainer/setup-kali.sh --start-only  # sadece konteyneri başlat
```

## GitHub Actions workflow'ları

| Workflow | Ne yapar |
| --- | --- |
| `docker-image.yml` | `push` / `pull_request` / manuel: config doğrular, shellcheck çalıştırır, `Dockerfile`'ı build eder |
| `docker-publish.yml` | Günlük / `main` push / `v*` etiketleri: imajı `ghcr.io/<owner>/<repo>` adresine push eder ve cosign ile imzalar |

Not: Docker-in-Docker özelliği Codespace konteynerini `--privileged` çalıştırır; bu yüzden
iç içe Docker istemiyorsanız "dogrudan" yapılandırmayı tercih edin.
