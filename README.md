<div align="center">

# 🐋 WinDoctor · 让 AI 帮你看一眼电脑到底哪儿不对

**把「我电脑好卡」变成「你这台机器的问题在页面文件，3 分钟能改好」**

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-lightgrey)
![Admin](https://img.shields.io/badge/管理员权限-部分需要-orange)
![No Upload](https://img.shields.io/badge/你的数据-一个字节都不上传-success)

[快速开始](docs/01-快速开始.md) · [为什么会卡](docs/02-为什么会卡.md) · [踩过的坑](docs/03-踩过的坑.md) · [安全检查清单](docs/04-安全检查清单.md) · [English](#english)

</div>

---

## ✨ 起因

有天我开个 Cursor，它直接崩了。不是卡，是窗口消失。

翻了半天日志，看到一行：

```
CodeWindow: renderer process gone (reason: oom, code: -536870904)
```

`oom` = out of memory。

一台 16 G 内存的机器，开个编辑器就内存不足？

查下去发现问题不止一个：

- 物理内存 16 G，可用只剩 **2 G**
- 页面文件被锁死在 **2 G**，而且不接受增长
- F 盘有个 **23 G 的 `pagefile.sys`**，创建于一年前，文件在那儿，配置里却没有——白占硬盘，一天没工作过
- 开机自启 **23 项**，加上任务计划里 10 个，微信 Steam Docker Ollama 网盘飞书浏览器全在后台
- 数据盘 D 的页面文件设了 16 G，但从没重启过，所以从来没生效

最后一点点捋完：

```
可用内存    2.09 GB  →  6.13 GB
提交上限   17.7 GB  →  35.7 GB
开机自启     23 项  →   7 项
系统服务     全自动  →  9 个改手动 / 2 个禁用 / 11 个停止
Cursor       一开就崩 →  正常打开
```

这个仓库就是整个过程。我把每一步的判断依据、命令、风险、还原方法都记下来了，写成 AI 能直接照着执行的格式。

---

## 🚀 怎么用

### 最省事：丢给 AI，让它带你做

把这段复制给你的 AI（ChatGPT / Claude / Kimi / DeepSeek / 本地模型都行）：

```
读一下这个仓库：
https://github.com/black-mouse-sha/win-doctor

然后按 AGENT-GUIDE.md 的流程，一步一步带我查我的 Windows 电脑。
一次只做一件事，动手前先说清楚要改什么、有什么风险，等我说可以了再动。
改之前先备份，改完把改前改后的值都打出来给我看。
```

它会先问你三个问题（电脑是不是公司的、装没装杀毒、主要拿来干嘛），然后一项一项来。

**不会一口气甩十条命令给你。**

### 想自己动手

```powershell
# 只读体检，不改任何东西
powershell -NoProfile -ExecutionPolicy Bypass -File .\check.ps1
```

输出会告诉你：内存够不够、页面文件配得对不对、开机自启有几个、有没有僵尸文件。

### 只想查某一项

直接翻 `modules/`，每篇都是独立的：

| 模块 | 查什么 |
|---|---|
| [开机自启](modules/01-开机自启.md) | 三个地方：注册表、启动文件夹、任务计划 |
| [系统服务](modules/02-系统服务.md) | 自动/手动/禁用到底怎么选 |
| [页面文件](modules/03-页面文件.md) | 这个最容易被网上教程坑 |
| [软件清理](modules/04-软件清理.md) | 装了但一年没打开的东西 |

---

## 🧠 几个大多数人搞错的点

### 页面文件不是「内存」

网上到处是这种教程：「虚拟内存设成 2 G，C 盘立刻多出 10 G」。

那是 2010 年代给 4 G 内存的老机器写的。你 16 G 内存的机器照做，结果是——

```
内存一满 → 只有 2 G 缓冲 → 一秒填满 → 系统只能杀程序
```

**它不增加你的内存。** 它干的事是：内存快满时，把暂时不用的数据（切走的标签、后台挂着的程序）挪到硬盘，腾出内存给新程序。

结果：

```
以前：内存满 → 程序被杀掉 → 你丢了工作
现在：内存满 → 卡一下（0.5~2 秒）→ 东西都还在
```

**从「会死」变成「会顿」。** 这就是全部。

### 「手动」不是「关掉」

服务有三种状态：

```
自动    开机就起，从早到晚在跑
手动    开机不起，要用的时候起
禁用    永远不起
```

大部分服务改成**手动**就够了，软件该用还能用。

但这里有个反直觉的地方，很多人踩过：

> **Windows 服务不会因为某个程序去连它而自动启动。**

Navicat 连 MySQL，MySQL 服务不会自己起来，只会「连接失败」。你得先 `net start MySQL80`，或者干脆把它留在「自动」。

所以：

```
数据库、驱动、软件一开就必须在的   →  留自动
更新器、遥测、辅助功能            →  改手动
Flash 这种已经死了的               →  禁用
```

### 「缓存小」和「跑 AI 慢」没关系

模型推理吃的是显存带宽和 GPU 算力，不是缓存。

如果 1.5 B 的小模型都慢，**九成是它根本没在用显卡，退回 CPU 在硬算了**。

打开任务管理器看 GPU 占用就知道了：

```
跑模型时 GPU 60~90%   →  正常
跑模型时 GPU 0~5%     →  确诊，在用 CPU
```

---

## 🧩 哪些能直接跑，哪些只能看

| 内容 | 能直接用？ | 说明 |
|---|---|---|
| `check.ps1` | ✅ 能跑 | **只读**，不改任何东西，随便跑 |
| `backup.ps1` | ✅ 能跑 | 把自启项和服务状态存一份 |
| `restore.ps1` | ✅ 能跑 | 按备份还原 |
| `modules/*.md` | 📖 看 | 带命令的教程，需要你自己判断要不要执行 |
| `scripts/` 里的提权脚本 | ⚠️ **要管理员** | 会改系统设置，跑之前先看清楚 |
| `docs/03-踩过的坑.md` | 📖 看 | 别人的血泪，能省你半小时 |

**一句话**：`check.ps1` 随便跑，`scripts/` 想清楚再跑，`modules/` 是给人读的。

---

## 📁 目录

```
win-doctor/
├── README.md                    ← 你在看的这个
├── AGENT-GUIDE.md               ← 给 AI 的说明书（核心）
├── check.ps1                    ← 一键体检（只读，安全）
├── backup.ps1                   ← 备份当前状态
├── restore.ps1                  ← 还原
├── modules/                     ← 分模块教程
│   ├── 01-开机自启.md
│   ├── 02-系统服务.md
│   ├── 03-页面文件.md
│   └── 04-软件清理.md
├── scripts/                     ← 需要管理员的操作脚本
│   ├── set-pagefile.ps1
│   ├── set-service-mode.ps1
│   └── remove-autostart.ps1
└── docs/
    ├── 01-快速开始.md
    ├── 02-为什么会卡.md
    ├── 03-踩过的坑.md
    └── 04-安全检查清单.md
```

---

## 🎯 适合谁

- **电脑开着开着程序自己消失的人** —— 大概率是 OOM，不是软件坏了
- **任务管理器里内存条天天 90% 的人** —— 先看看页面文件配对没
- **被「一键优化」坑过的人** —— 这个仓库告诉你那些优化到底改了什么
- **想帮家里长辈收拾电脑的人** —— `check.ps1` 跑一遍，问题一目了然
- **跑本地大模型觉得慢的人** —— 先确认它到底用没用上显卡

**不适合**：服务器、域控环境、有组策略管着的公司电脑。那些地方别乱动。

---

## 🔒 关于数据

`check.ps1` 只读本机信息并打印到屏幕。

```
不联网
不上传
不收集
不写日志到外面
```

所有的判断都在你本地完成。仓库里也没有任何人的机器信息——路径、用户名、序列号在整理时都做了替换。

---

## ⚠️ 动手之前

```
1. 重要文件先备份
2. 公司电脑先问 IT（那些零信任客户端关了可能连不上内网）
3. 杀毒软件的服务一个都别动
4. 不确定的服务，先改成「手动」观察一周，别直接禁用
```

每一处改动都配套了还原方法。真出问题了，`restore.ps1` 或者手动改回去。

---

## ⭐ 如果它帮到你了

点个 Star 吧，也让更多被「一键优化」坑过的人找到这儿。

欢迎：

- 🐛 **开 Issue** —— 报 bug、说「我这里跑不通」、贴你的 `check.ps1` 输出都行
- 📝 **补模块** —— 你踩过的坑，写下来别人就不用再踩
- 🔧 **改脚本** —— 哪个判断不准，直接提 PR

---

## 🙏 致谢

- **[DeepSeek Harness](https://github.com/deepseek-ai)** —— 这次的排查就是在它上面一步步跑出来的
- **[mihomo](https://github.com/MetaCubeX/mihomo)** —— 排查代理问题时靠它的 named pipe API 才测出 12 个节点全不通
- 以及所有在网上留下真实排查记录的人。这个仓库里有一半的坑，是别人先踩过我才没踩的

---

## 📄 许可

MIT。随便用，随便改，出了问题自己负责。

---

<div align="center"><sub>Made with 🐋 and one very stubborn OOM · 如果你也刚被「内存不足」坑过，欢迎来聊聊</sub></div>

---

## English

**WinDoctor** — an AI-guided Windows health checkup.

The story: a 16 GB laptop with 2 GB free RAM. Pagefile locked at 2 GB. A 23 GB zombie `pagefile.sys` sitting unused for a year. 23 startup entries. Cursor crashed on launch with `oom`.

After the cleanup: **free RAM 2 GB → 6 GB, commit limit 17.7 GB → 35.7 GB.**

This repo records every step — the commands, the reasoning, the risks, and how to undo each change — in a format an AI can follow.

```powershell
# Read-only health check
powershell -NoProfile -ExecutionPolicy Bypass -File .\check.ps1
```

Or hand the repo URL to your AI assistant and say: *"Read AGENT-GUIDE.md and walk me through this, one step at a time."*

**No network calls. No telemetry. Nothing leaves your machine.**

MIT licensed.
