# Sekia_URP_TechDemo
介绍：这是我个人学习渲染技术的效果与技术展示demo。  
仓库地址：https://github.com/Acgmart/Sekia_URP_TechDemo  
Unity官方仓库地址：https://github.com/Unity-Technologies/Graphics
测试环境：  
Unity版本：[2022.1b](https://unity3d.com/beta/2022.1b#downloads)(保持更新到最新的beta版本  
URP版本：[13.1.5](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@13.1/manual/index.html)(保持同步最新的改动  

# 渲染流程方案


# 主要渲染技术
SMAA用于静态图像 TAA用于动态图像
各种AA算法对比：https://vr.arvilab.com/blog/anti-aliasing
FXAA原理：模糊亮度急剧变化的地方 损失对比度细节令人无法接受
SMAA原理：识别线条、曲线、物体边界形式的pattern并模糊他们
	FXAA在几何锯齿处理的比SMAA好 SMAA很多边没识别到
TAA原理：每帧偏移0.5-1个像素，渲染MotionVectorsBuffer

# 场景美术表现支持

# 笔记
美术向技术：
	每个像素的着色主要受到 光照-色调映射 影响
	光照 风格化渲染的核心-突出想表达的细节
	色调映射 调整画面的氛围
美术迭代思路：
	对项目美术风格的把控 落地在光照和色调映射上
	确定好美术风格、所见即所得是最优先事项
		对标原神、香港漫画、永劫无间等不同画风的商业作品
		提炼细节、层次感指标 在不同人设/表情/动作、环境上验证
	DCC工具链扩展 提高制作环节的生产效率
	HDR？
程序向技术：
	场景内的物体会进行互动 体现出画面的层次感
		SSAO等AO方案 增强实时物体与场景的融合度
		TAA等抗锯齿方案 改善动态场景像素的高频闪烁
		SSR等反射方案 增加反射细节
		GI方案 提供环境漫反射与环境镜面反射光源
		结合美术风格开发 先从无到有 再优化性能
	面向GamePlay制作复杂的表现系统
		武打 部位打击 伤残 身体平衡
		捏人换装 动态骨骼 布料
		AI
	