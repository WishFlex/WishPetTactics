# 更新说明 / Changelog

## 6.1.87

### 中文
- 为队伍的每个宠物槽位配置有序备用宠物及各自技能；优先使用符合血量要求的同种宠物，再按备用顺序选择。血量换宠仅在战斗结束后进行。
- 自动保存血量换宠设置；复活宠物冷却就绪时可切回 1 队及保存的原始宠物。
- 宠物搜索支持使用中英文逗号组合多个条件，例如“增压，召唤闪电”。
- 新增更新引导，点击条目可进入相关功能；完整和极简模式侧边栏均可打开更新日志。
- 优化目标窗口与宠物悬浮卡，减少打开和快速划过宠物时的额外工作，并调整显示设置的间距。

### English
- Configure ordered backup pets and abilities for each team slot. Eligible duplicates of the same species are prioritized; health-based replacements happen after battle.
- Save health thresholds immediately and optionally restore team 1 and its saved original pets when Revive Battle Pets becomes ready.
- Combine pet search terms with Chinese or English commas, such as “Supercharge, Call Lightning”.
- Added an update guide with links to related features and a sidebar entry in both Full and Minimal modes.
- Reduced extra work in the target window and when moving across pet tooltips, and tightened display-settings spacing.

## 6.1.71

### 中文
- 修复宠物对战中重载（`/reload`）后无法继续按脚本释放技能的问题。
- 优化换宠选择界面：移除多余木框、头像框、血条与暗色遮罩，仅保留纯净的 3D 宠物模型并在阵亡模型上显示红色死亡 X 图标。
- 调整战斗监控面板角色经验条高度（增加 2 像素）并将边框改为 50% 灰色。

### English
- Fixed script execution failing to resume after `/reload` during pet battles.
- Streamlined the pet selection strip by removing extra frames, icons, health bars, and dark overlays, leaving only clean 3D pet models with a standalone red X icon on dead pets.
- Increased the battle monitor player XP bar height by 2px and updated its border color to 50% gray.

## 6.1.50

### 中文
- 显示 HUB 时，隐藏按钮带有“隐藏界面”文字。隐藏后，恢复提示在图标上方显示两秒。
- 放大恢复图标，将它移至屏幕右下侧并提升显示层级，避开原生对战操作区。

### English
- Added a Hide HUB label to the button. After hiding the HUB, the restore hint stays above the icon for two seconds.
- Enlarged the restore icon and moved it to a higher layer near the lower right, away from the default battle controls.

## 6.1.49

### 中文
- 隐藏 HUB 后仅保留图标，并在图标上方短暂显示“点击图标显示 HUB”提示。
- HUB 底部的执行脚本、编辑脚本和快捷键按钮按可用宽度等宽排列，缩放控件与按钮间距统一。

### English
- When the HUB is hidden, only its icon remains; a brief “Click the icon to show the HUB” hint appears above it.
- The execute, edit script, and hotkey buttons share the available bottom-row width equally, with consistent spacing around the scale controls.

## 6.1.48

### 中文
- 缩小目标队伍宠物悬浮卡，合并等级、品质、品种、宠物类型和战斗属性，减少空白。
- 每个 GitHub Release 都从本文件读取对应版本的中英文更新说明。

### English
- Reduced target-team pet tooltip size by combining level, quality, breed, pet type, and battle stats into compact rows.
- GitHub Releases now include the Chinese and English notes for each version from this changelog.
