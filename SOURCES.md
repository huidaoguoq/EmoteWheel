# 表情素材来源

图库索引收录 CommunityDragon 中 **2,400 张正式表情**（包括《英雄联盟》、云顶之弈），索引整理日期为 2026-10-12。1.3.0 的安装包只携带 8 张默认 PNG，用户可在应用配置页一键下载完整图库；已经缓存的图片可离线使用，更新应用不清空缓存。全库原始图片合计约 198.7 MiB，CDN 压缩后的实际流量可能更小。

Git 仓库保存索引、下载清单和 `Resources/starter-emotes/` 中的 8 张默认图片，ID 为 1505、1459、3159、3154、1506、1498、1499、1030。应用内下载的图片保存在各平台的应用数据目录，PNG 成功解码后才写入缓存。

- [英文索引](https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/default/v1/summoner-emotes.json)
- [简体中文索引](https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/zh_cn/v1/summoner-emotes.json)
- [逐张下载地址和校验值](Resources/emotes-sources.json)

索引共 2,410 条。ID 1、2、4、5、6、7、8、9、10 是没有图片路径的熟练度等占位记录，无法作为图片表情加入。ID 0 的 FPO 开发占位图也未加入图库。其余 2,400 张在建立索引时已下载并完成 PNG 解码验证。

开发者可额外运行 `python3 -m pip install -r scripts/requirements.txt` 和 `python3 scripts/download_emotes.py`，将完整素材归档到源码目录的 `Resources/emotes/`；加 `--verify-only` 可离线校验。此脚本是可选工具，不是构建应用的前置步骤，下载的归档也不会自动加入标准安装包。

清单固定每张原始 PNG 的 SHA-256，以及尺寸和规范化 RGBA 像素的 SHA-256。CDN 的 Cloudflare Polish 会重新压缩 PNG，还可能改变 alpha 为 0 的完全透明像素中的 RGB 值；这些变化不会改变显示效果。归档脚本先检查原始文件哈希，不匹配时解码图片，将完全透明像素的 RGB 归零，再检查尺寸与像素哈希。可见像素和 alpha 必须完全一致，不接受近似匹配或有损变化。Pillow 仅是归档工具的依赖，应用内下载使用各平台的 PNG 解码能力。

latest 是动态地址，未来实际图像可能变化；归档脚本在上述校验均不匹配时失败，不会自动修改清单或接受新图片。应用内下载不做归档级哈希校验，使用来源清单中的 URL 并验证图片能够解码。

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
