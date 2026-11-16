# Termux packages

![GitHub repo size](https://img.shields.io/github/repo-size/termux/termux-packages)
[![Packages last build status](https://github.com/termux/termux-packages/actions/workflows/packages.yml/badge.svg?branch=master)](https://github.com/termux/termux-packages/actions)
[![Docker image status](https://github.com/termux/termux-packages/workflows/Docker%20image/badge.svg)](https://hub.docker.com/r/termux/package-builder)
[![Repology metadata](https://github.com/termux/repology-metadata/workflows/Repology%20metadata/badge.svg)](https://repology.amdmi3.ru/repository/termux)

[![Join the Termux Discord server](https://img.shields.io/discord/641256914684084234.svg?label=&logo=discord&logoColor=ffffff&color=5865F2)](https://discord.gg/HXpF69X)
[![Join the Termux space on Matrix](https://img.shields.io/badge/Matrix-%E2%80%8B?style=plastic&logo=matrix&logoColor=white&color=green)](https://matrix.to/#/#Termux:matrix.org)
[![Join the Termux server on Telegram](https://img.shields.io/badge/Telegram-%E2%80%8B?style=plastic&logo=telegram&logoColor=white&color=blue)](https://t.me/termux24x7)
[![Official subreddit](https://img.shields.io/badge/Reddit-%E2%80%8B?style=plastic&logo=reddit&logoColor=white&color=red)](https://www.reddit.com/r/termux/)

[![Repository status](https://repology.org/badge/repository-big/termux.svg)](https://repology.org/repository/termux)

<img src=".github/static/hosted-by-hetzner.png" alt="Hosted by Hetzner" width="128px"></img>

This project contains scripts and patches to build packages for the [Termux](https://github.com/termux/termux-app)
Android application.

Quick how-to about Termux package management is available at [Package Management](https://github.com/termux/termux-packages/wiki/Package-Management). It also has info on how to fix **`repository is under maintenance or down`** errors when running `apt` or `pkg` commands.

## Contributing

Read [CONTRIBUTING.md](/CONTRIBUTING.md) and [Developer's Wiki](https://github.com/termux/termux-packages/wiki) for more details.

## Publish repository

Các gói build xong được đưa lên APT repository tại
<https://wizk-repos.chuong.qzz.io/wizkterm-main>.

Bucket Cloudflare R2 `wizk-repos` là nguồn dữ liệu duy nhất: vừa chứa pool `.deb`,
vừa chứa metadata (`Packages`, `Contents`, `Release`, `InRelease`).
Không còn dùng GitLab repo hay GitLab Pages.

Workflow `.github/workflows/packages.yml` (job `upload`) chạy `scripts/publish-repo.sh`:

1. `rclone sync` kéo toàn bộ bucket về thư mục nháp.
2. Chép `.deb` mới vào pool, xoá bản cũ của cùng gói.
3. Sinh `Packages`/`Contents`/`Release`, ký GPG thành `InRelease` và `Release.gpg`.
4. `scripts/verify-apt-repo.sh` kiểm tra chữ ký và checksum.
5. `rclone sync` đẩy ngược thư mục nháp lên bucket.

Cần đặt các secret sau trong GitHub repository settings:

| Secret | Nội dung |
| --- | --- |
| `R2_ACCESS_KEY_ID` | Access key ID của R2 token |
| `R2_SECRET_ACCESS_KEY` | Secret access key của R2 token |
| `R2_ENDPOINT` | Endpoint S3, dạng `https://<account-id>.r2.cloudflarestorage.com` |
| `GPG_PRIVATE_KEY` | Khoá riêng ASCII-armored dùng để ký `Release` |
| `GPG_PASSPHRASE` | Passphrase của khoá ký |
| `GPG_KEY_ID` | Key ID của khoá ký |

Và các variable (Settings → Variables):

| Variable | Nội dung |
| --- | --- |
| `R2_BUCKET` | Tên bucket, mặc định `wizk-repos` |
| `R2_PUBLIC_URL` | URL công khai, `https://wizk-repos.chuong.qzz.io` |

Chạy tay:

```bash
export R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_ENDPOINT=https://<account>.r2.cloudflarestorage.com
./scripts/publish-repo.sh --debs <thư mục chứa .deb> --work <thư mục nháp>
```

Thêm `--dry-run` để dựng và kiểm tra metadata ở địa phương mà không đụng vào bucket.


## Community

The Termux Community docs are available [here](https://github.com/termux/termux-community/blob/site/site/pages/en/index.md).

**All our community members must follow the rules that are defined [here](https://github.com/termux/termux-community/blob/site/site/pages/en/rules/index.md) and any [Content Not Allowed](https://github.com/termux/termux-community/blob/site/site/pages/en/rules/index.md#8-content-not-allowed) must not be posted.**
##



## Sponsors and Funders

[<img alt="GitHub Accelerator" width="25%" src="site/assets/sponsors/github.png" />](https://github.com)  
*[GitHub Accelerator](https://github.com/accelerator) ([1](https://github.blog/2023-04-12-github-accelerator-our-first-cohort-and-whats-next))*

&nbsp;

[<img alt="GitHub Secure Open Source Fund" width="25%" src="site/assets/sponsors/github.png" />](https://github.com)  
*[GitHub Secure Open Source Fund](https://resources.github.com/github-secure-open-source-fund) ([1](https://github.blog/open-source/maintainers/securing-the-supply-chain-at-scale-starting-with-71-important-open-source-projects), [2](https://termux.dev/en/posts/general/2025/08/11/termux-selected-for-github-secure-open-source-fund-session-2.html))*

&nbsp;

[<img alt="NLnet NGI Mobifree" width="25%" src="site/assets/sponsors/nlnet-ngi-mobifree.png" />](https://nlnet.nl/mobifree)  
*[NLnet NGI Mobifree](https://nlnet.nl/mobifree) ([1](https://nlnet.nl/news/2024/20241111-NGI-Mobifree-grants.html), [2](https://termux.dev/en/posts/general/2024/11/11/termux-selected-for-nlnet-ngi-mobifree-grant.html))*

&nbsp;

[<img alt="Cloudflare" width="25%" src="site/assets/sponsors/cloudflare.png" />](https://www.cloudflare.com)  
*[Cloudflare](https://www.cloudflare.com) ([1](https://packages-cf.termux.dev))*

