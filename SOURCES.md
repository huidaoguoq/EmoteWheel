# 表情素材来源

内置 CommunityDragon 当前索引中全部 **2,400 张正式表情 PNG**（包括《英雄联盟》、云顶之弈）。下载日期：2026-10-12。构建后的应用包含全库图片，启动和使用无需联网。原始图片合计约 198.7 MiB。Git 仓库不提交图片文件，仅保留索引与下载清单；运行 `python3 scripts/download_emotes.py` 下载，或加 `--verify-only` 离线校验。

- [英文索引](https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/summoner-emotes.json)
- [简体中文索引](https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/zh_cn/v1/summoner-emotes.json)
- [逐张下载地址和校验值](Resources/emotes-sources.json)

索引共 2,410 条。ID 1、2、4、5、6、7、8、9、10 是没有图片路径的熟练度等占位记录，无法作为图片表情加入。ID 0 的 FPO 开发占位图也未加入图库。其余 2,400 张已全部下载并完成 PNG 解码验证，无下载失败。清单固定了每张图片的 SHA-256。latest 是动态地址，未来内容可能变化；下载器在校验不匹配时失败，不会自动修改清单或接受新图片。

名称主要采用游戏简体中文数据；最初 16 张保留已有的易读名称，原中文名称可用于搜索。搜索同时支持英文名称、ID，以及少量常用别名。

| ID | 官方名称 | 常用搜索词 |
| --- | --- | --- |
| 3236 | 弱爆 / Unworthy | 塞拉斯、倒拇指、无字 |
| 3239 | 弱爆 / Unworthy | 塞拉斯、倒拇指、有字 |
| 4361 | 这… / Sweat Drop | 流汗、刀妹、艾瑞莉娅、尴尬 |
| 4681 | 流汗布里茨 / Sweating Blitzcrank | 流汗、机器人、布里茨 |
| 3565 | -_-\|\| 汗 / You Really Thought... | 流汗、芮尔 |

## 版权与使用

《英雄联盟》、角色与表情图像的相关权利归 Riot Games 所有。CommunityDragon 为社区维护的数据与资源镜像。本项目是非官方的本地桌面工具，与 Riot Games 无关联，未获其背书。本项目不声明拥有 Riot Games 素材的分发授权。

## 交互参考

- [Riot 官方 Emotes FAQ](https://support.riotgames.com/en-us/league-of-legends/gameplay/emotes-faq)
- [英雄联盟表情轮盘](https://wiki.leagueoflegends.com/en-us/Emote)

本工具按用户指定使用 Y 作为默认快捷键，采用八向选择、中心取消与松开发送的桌面交互。

## 应用签名参考

- [Apple TN3127: Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)：代码签名要求、应用身份与更新匹配。
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)：Developer ID 分发和公证流程。
