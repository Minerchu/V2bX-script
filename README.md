# V2bX-script（带伪装站点）

V2bX 一键安装脚本，**装完自动在 443 上跑一个随机企业官网**。

浏览器打开域名看到的是公司网站，代理客户端连上去是正常的 vless 节点。
节点配置、订阅、客户端全部零改动。

```
https://你的域名/          →  企业官网（13 个页面）
https://你的域名/<路径>    →  代理握手（101）
```

原项目：[wyx2685/V2bX-script](https://github.com/wyx2685/V2bX-script)
伪装站点：[Minerchu/hkbt-deploy](https://github.com/Minerchu/hkbt-deploy)

---

## 一键安装

```bash
wget -N https://raw.githubusercontent.com/Minerchu/V2bX-script/master/install.sh && bash install.sh
```

> BusyBox 的 wget 没有 `-N`，Alpine 上改用：
> `curl -fsSL https://raw.githubusercontent.com/Minerchu/V2bX-script/master/install.sh -o install.sh && sh install.sh`

### 支持的系统

| 系统 | init | 说明 |
|---|---|---|
| Debian 11+ / Ubuntu 20+ | systemd | 默认支持 |
| Alpine 3.18+ | OpenRC | 自动装 bash、用 `rc-service` 管理服务、`cron` 做定时同步 |
| RHEL / Rocky / Alma | systemd | 默认支持 |

两种 init 系统的差异脚本自己处理，不用改命令：

| | systemd | OpenRC |
|---|---|---|
| 启停服务 | `systemctl` | `rc-service` |
| 开机自启 | `systemctl enable` | `rc-update add` |
| 看日志 | `journalctl -u V2bX` | `tail /var/log/V2bX.log` |
| 定时同步 | `hkbt-sync.timer` | `cron` |
| 重启钩子 | systemd drop-in | init 脚本的 `post_start()` |

用 `sh install.sh` 启动也行 —— Alpine 上没有 bash 时会先 `apk add bash` 再重新执行自己。

安装流程和原版完全一样（选核心、填面板地址、API Key、节点 ID、证书模式），
**最后会多两步**：

1. 确认 V2bX 真的跑起来了（服务 active、节点端口在监听、启动日志没有致命错误），
   才继续；代理没起来就直接停下，不碰 443。
2. 等证书签发完成后，自动生成一个随机企业站并接管 443，再挂一个配置同步任务。

> **端口和路径都不用填。** 这两项由 V2bX 自己从面板拉取，安装脚本只是把拉到的值打印出来给你核对。
> 你唯一需要提供的是面板对接信息（ApiHost / ApiKey / NodeID），那是 V2bX 自己运行也需要的。

安装结束后会打印：

```
==========================================================
  伪装站点已就绪
==========================================================
  网站地址   https://你的域名/
  部署面板   https://你的域名/__deploy-xxxxxxxx/
  面板密码   xxxxxxxxxxxx
  网站名称   明远实业
  站点模板   logistics
  对外端口   443
  代理端口   20000
  代理路径   /sdf=?kfj
==========================================================
```

面板密码同时保存在 `/opt/hkbt-deploy/panel-password.txt`（权限 600）。

---

## 随机是怎么随机的

每次安装独立随机，两台机器不会长得一样：

- **11 套行业模板**：通用商贸、化妆品、纺织、医疗、食品、物流、家居、汽配、化工、电子、机械
- **30 个中性企业名**：远洋实业、恒通国际、锦程集团、嘉禾实业、鼎盛国际……

每套模板都是 13 个页面，含配图、PDF 单据、3 篇行业文章，内容不是占位符。

想固定某一套，安装后可以在面板里重新部署，或者手动指定：

```bash
cd /opt/hkbt-deploy
python3 app.py --init --port 443 --template cosmetic --brand 妆研生物 --password '你的密码'
```

---

## 跳过自动部署

```bash
HKBT_SKIP=1 bash install.sh
```

适合已经有站点、或者只想装代理的情况。

装完之后想补上，随时手动跑：

```bash
curl -fsSL https://raw.githubusercontent.com/Minerchu/V2bX-script/master/hkbt.sh | bash
```

---

## 它做了什么

| 步骤 | 说明 |
|---|---|
| 读节点 | 从 `config.json` + 面板 API 拿域名、端口、路径（拿不到就中止，不猜） |
| **等代理就绪** | 服务 active + 节点端口在监听 + 日志无致命错误，最多 150 秒 |
| 等证书 | 轮询 `CertConfig.CertFile`，最多 180 秒 |
| 装依赖 | nginx、python3-flask（已有则跳过） |
| 拉代码 | 下载 hkbt-deploy 到 `/opt/hkbt-deploy` |
| 部署站点 | 随机模板 + 随机品牌，生成 13 页站点到 `/var/www/hkbt` |
| 接管 443 | nginx 监听 443，按路径分流到代理端口 |
| **装同步** | V2bX 重启即触发 + 每 3 分钟兜底，面板改了端口/路径自动跟上 |

### 为什么先等代理就绪

代理配置写错时（节点 ID 不对、端口被占、证书路径错），V2bX 会反复重启失败。
如果这时候先把 Nginx 挂上 443，会出现「网站正常 + 代理不通」的混合状态，
排查时分不清是代理挂了还是分流写错了。

所以顺序是：**先确认代理能用，再配网站**。代理没起来时脚本会打印日志里的致命行并退出，
443 空着反而是好事 —— 只有一个问题要查。

```bash
# 三道检查，任何一道不过就停
systemctl is-active V2bX
ss -tlnp | grep -E 'V2bX|sing-box'
journalctl -u V2bX -n 200 | grep -iE 'panic|fatal|address already in use|invalid config'
```

端口在监听就直接放行（代理确实可用）；没监听才去看日志找原因。

### 端口和路径从哪来

V2bX 的 `config.json` 里**只有 NodeID 和 API 凭据**，真正的 `server_port` 和 ws `path`
是它启动时从面板 API 拉的，磁盘上没有副本。所以本站也走同一个来源：

```
/etc/V2bX/config.json  ──ApiHost/ApiKey/NodeID──▶  面板 API
                                                     │
                       ┌─────────────────────────────┘
                       ▼
        server_port + networkSettings.path
                       │
                       ▼
        nginx location 与 proxy_pass
```

安装时会打印实际读到的值：

```
[HKBT] 从面板读取节点端口与路径（无需手工填写）
  节点域名   jpcdn.example.com
  代理端口   20000  ← 面板读取
  代理路径   /sdf=?kfj  ← 面板读取
  节点类型   ws / TLS
```

兼容 V2board 与 Xboard 两套字段（`networkSettings` / `network_settings`，含 `data` 包装层）。

**读不到就不部署。** 如果面板不可达，或节点是 tcp / reality 这类没有 path 的类型，
脚本会直接中止并列出排查项 —— 因为猜一个默认路径会让 Nginx 分流与节点不一致，
表现为客户端握手能过、随即断开，比直接报错难查得多。

只有一种情况会用本地记录：面板完全不可达、但本机上次部署成功过。
此时会明确提示「沿用上次记录的路径」，面板改过 path 的话需要先恢复连通再部署。

### 端口怎么分配

| 节点端口 | nginx | sing-box | 说明 |
|---|---|---|---|
| 20000 等非 443 | 443 | 保持 20000 | 客户端填 20000，443 按路径转发过去 |
| 443 | 443 | 收窄到 127.0.0.1:443 | 同端口，靠绑定地址区分 |

**面板里的端口永远填 443**。填代理端口会被校验拒绝，因为 nginx 绑不上。

### 代理端口也是网站

节点端口是 20000 时，`https://域名:20000/` 默认会返回 sing-box 的空 404 —— 一眼就能看出不是网站。
部署时会自动加一条 NAT 重定向，把外部到 20000 的连接转到 443：

```
https://域名/           → 网站
https://域名:20000/     → 网站（NAT 转到 443，同样由 nginx 处理）
https://域名/<path>     → 代理
https://域名:20000/<path> → 代理
```

规则写成 `hkbt-nat.service`，开机自动加载；改端口后重新部署会先清旧规则。
不想开的话：`HKBT_NO_CAMOUFLAGE=1 bash hkbt.sh`（或部署后 `systemctl disable --now hkbt-nat`）。

> 副作用：代理看到的客户端 IP 变成 `127.0.0.1`。流量统计按 UUID 算不受影响，
> 但面板若开了「同 IP 设备数限制」，多设备可能被算成一个。

### 面板改了端口/路径，网站会自己跟上

节点端口和路径是 V2bX **运行时从面板拉**的，本机磁盘上没有副本；Nginx 的
`location` 和 `proxy_pass` 却是静态的。面板一改，V2bX 跟着变，Nginx 不知道 ——
表现就是「网站还开着，代理全连不上」。

装完会自动启用两个触发点：

| 触发 | 频率 | 作用 |
|---|---|---|
| `V2bX` 重启 | 每次重启 | drop-in 里的 `ExecStartPost`，立刻同步一次 |
| `hkbt-sync.timer` | 每 3 分钟 | 兜底。面板上只改端口不会重启 V2bX，只能轮询发现 |

同步只做一件事：比对面板最新值和 Nginx 配置里的指纹，不一致才重写 + 重载。

```nginx
# hkbt-fingerprint: jpcdn.cctv6.de|443|/sdf=?kfj|20000
#                  域名          对外端口 路径     代理端口
```

手动触发：

```bash
python3 /opt/hkbt-deploy/app.py --sync
systemctl list-timers hkbt-sync.timer
journalctl -u hkbt-sync -n 30
```

**取不到值时一律不动。** 面板临时不可达、证书续期时文件闪一下、节点被临时改成 tcp ——
这些都不会去改配置，只在日志里记一笔。因为 443 已经在服务了，为了一次抖动把站点拆掉不划算。

同步间隔可以改：

```bash
python3 /opt/hkbt-deploy/app.py --install-sync --sync-interval 10   # 10 分钟
HKBT_NO_SYNC=1 bash hkbt.sh                                        # 装的时候不挂同步
```

### 面板能做什么

`https://域名/__deploy-xxxxxxxx/`，随机路径，不额外开端口：

- 查看状态（域名、端口、路径、证书到期、监听情况）
- 重新部署（换模板、换品牌、上传自己的站点 zip）
- 运行自检（6 项）
- 回滚到上一次部署

---

## 常见问题

**装完网站打不开？**

```bash
# systemd
systemctl status nginx
journalctl -u V2bX -n 50 --no-pager

# OpenRC（Alpine）
rc-service nginx status
tail -50 /var/log/V2bX.log

curl -sk -o /dev/null -w "%{http_code}\n" https://你的域名/
```

最常见的原因是证书还没签下来（域名没解析到本机、面板节点没配好）。

**代理连不上？**

路径必须与面板节点完全一致。带 `?` 和 `=` 的路径（如 `/sdf=?kfj`）要原样填。
脚本已在服务端兼容 `/sdf`、`/sdf?kfj`、`/sdf=?kfj` 三种写法。

**在面板里改了节点路径或端口？**

不用管，会自动跟上。V2bX 重启后立刻同步一次，之后每 3 分钟检查一次，
最长 3 分钟内 Nginx 就会换成新的端口和路径。

想立刻生效：

```bash
python3 /opt/hkbt-deploy/app.py --sync
```

看到「配置一致，无需变更」说明本来就是对的；看到「已同步」说明刚才已经改过来了。

如果输出「跳过：面板 API 不可达」，那是面板本身连不上，不是同步的问题 ——
这时保持原配置不动是故意的，避免站点下线。

**能连上但网页打不开？**

机器没有 IPv6 出口，但 DNS 返回了 IPv6 地址。安装脚本会自动检测并设置 IPv4 优先，
如果还是不行，看 [TROUBLESHOOTING 第 12 条](https://github.com/Minerchu/hkbt-deploy/blob/master/TROUBLESHOOTING.md)。

**会不会影响原来的节点？**

不影响。sing-box 的端口、证书、面板配置都不动，只是多了一个 nginx 在前面。

---

## 软件更新

```bash
v2bx update
```

更新只替换 V2bX 二进制，不会动 nginx 配置和站点文件。
更新完 V2bX 会重启，同步任务自动触发一次 —— 如果新版改了什么默认值，
Nginx 也会跟着对齐，不用手动处理。

> 同步钩子写在 `V2bX.service.d/20-hkbt-sync.conf` 这个 drop-in 里，
> 不在主单元文件内，所以 `v2bx update` 覆盖主单元时它不会丢。

---

## 详细教程

- V2bX 配置：[v2bx.v-50.me](https://v2bx.v-50.me/)
- 伪装站点原理与排障：[hkbt-deploy](https://github.com/Minerchu/hkbt-deploy)
