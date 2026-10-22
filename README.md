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

安装流程和原版完全一样（选核心、填面板地址、API Key、节点 ID、证书模式），
**最后会多一步**：等证书签发完成后，自动生成一个随机企业站并接管 443。

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
| 等证书 | 轮询 `CertConfig.CertFile`，最多 180 秒 |
| 装依赖 | nginx、python3-flask（已有则跳过） |
| 拉代码 | 下载 hkbt-deploy 到 `/opt/hkbt-deploy` |
| 读节点 | 从 `config.json` + 面板 API 拿域名、端口、路径 |
| 部署站点 | 随机模板 + 随机品牌，生成 13 页站点到 `/var/www/hkbt` |
| 接管 443 | nginx 监听 443，按路径分流到代理端口 |

### 端口怎么分配

| 节点端口 | nginx | sing-box | 说明 |
|---|---|---|---|
| 20000 等非 443 | 443 | 保持 20000 | 客户端填 20000，443 按路径转发过去 |
| 443 | 443 | 收窄到 127.0.0.1:443 | 同端口，靠绑定地址区分 |

**面板里的端口永远填 443**。填代理端口会被校验拒绝，因为 nginx 绑不上。

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
systemctl status nginx
curl -sk -o /dev/null -w "%{http_code}\n" https://你的域名/
journalctl -u V2bX -n 50 --no-pager
```

最常见的原因是证书还没签下来（域名没解析到本机、面板节点没配好）。

**代理连不上？**

路径必须与面板节点完全一致。带 `?` 和 `=` 的路径（如 `/sdf=?kfj`）要原样填。
脚本已在服务端兼容 `/sdf`、`/sdf?kfj`、`/sdf=?kfj` 三种写法。

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

---

## 详细教程

- V2bX 配置：[v2bx.v-50.me](https://v2bx.v-50.me/)
- 伪装站点原理与排障：[hkbt-deploy](https://github.com/Minerchu/hkbt-deploy)
