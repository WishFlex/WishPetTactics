# WishPetTactics

WishPetTactics 是《魔兽世界》正式服的宠物对战插件，提供队伍管理、目标绑定、对战脚本和战斗 HUD。

- 给 NPC 绑定多支队伍，按顺序准备出战，并可替换低血量或阵亡的同种宠物。
- 在目标窗口悬停宠物头像，查看出战技能、品质、等级和属性。
- 用快捷键执行对战脚本，在 HUD 查看战斗计时、技能和复活冷却。HUD 支持缩放和切换回原生界面。
- 可开启战后换队信息，在屏幕和本地聊天框查看队伍状态。

从 [Releases](https://github.com/WishFlex/WishPetTactics/releases) 下载 `WishPetTactics-版本号.zip`，解压到 `World of Warcraft/_retail_/Interface/AddOns/`。确认 `AddOns/WishPetTactics/WishPetTactics.toc` 存在，然后在游戏内启用插件。已登录时可输入 `/reload`。

## English

WishPetTactics is a Retail World of Warcraft addon for managing battle pet teams, binding teams to NPC targets, running battle scripts by hotkey, and displaying pet battle information in a configurable HUD.

Download the versioned ZIP from [Releases](https://github.com/WishFlex/WishPetTactics/releases), extract it into `_retail_/Interface/AddOns/`, and enable WishPetTactics in game.

## 发布新版本 / Publishing a release

更新插件 TOC 中的版本并提交到 GitHub，再推送匹配的版本标签，例如 `v6.1.47`。GitHub Actions 会生成包含 `WishPetTactics/` 的 ZIP，并将其附到 Release。

Push a version tag matching the addon's TOC version to build and publish the ZIP automatically.
