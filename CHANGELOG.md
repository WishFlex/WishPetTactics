# 更新说明 / Changelog

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
