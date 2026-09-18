# -*- coding: utf-8 -*-
"""分镜稿配额自检（小家提示词生成器 v13.1.1 成稿）

用法:
    python quota_check.py <分镜稿路径> [更多路径...] [--max15 N] [--dur N] [--rules DIR]

输出:
    A. 章节级：镜数、总时长、时长分布、>10s 镜计数与上限、全稿总字数
    B. 逐镜：①/②/③/④ 字数、拍数、拍相加、每拍字数
    C. 证据项密度：@imageN 锚定、承接复述、占画框（尺度四件套代理）、隐形剪辑点
    D. 违规分档：硬项（必修）与软项（已知同级规则冲突，按项目裁决）
    E. 运镜标签（铁律52 视觉目标）——先按①段画质基准分轨，再分四层判：
       ① 分轨标志：①段含 `Path Tracing` = 打戏镜；含 `BJD人偶风` = 文戏镜
       ② 打戏镜③段必须出现视觉目标标签（跟*/展*/聚焦*/压迫*/收束*/反馈*…）；一个都没有
          ＝漏绑视觉目标 → 硬项（铁律0.5/20/52 均要求正文每拍绑 `[视觉目标]`）
       ③ 文戏镜不该出现视觉目标标签（20 号标杆示例明文"不贴标签"）→ 出现即软项提示
       ④ 越界用词：凡不在规则源清单内的标签逐个列出，形如视觉目标者计入硬项
       清单来源 = 规则源方括号标签 ∪ 「视觉目标（…）」纯文本枚举（v13.1.1 下 235 个，运镜目标族 44 个）
    F. 锁死画质原文覆盖率：①段对「打戏 11 号 2.1 / 文戏 20 号 3.1」锁死原文的特征表述命中率。
       用途＝证明①段确实由规则原文派生（专治"没读就编"）。**信息项，不做通过/否决**——规则
       自己要求「落稿压成 2-3 句连贯话、正文不分号罗列长清单」，故表述未命中不等于违规。
    G. 尺度四件套（铁律19）：逐拍统计「画框分数占比」「参照物」两类字面证据的覆盖率，
       并列出"疑似特效拍却无画框分数"的疑点拍。**信息项，不做通过/否决**——本项按「拍」统计，
       而铁律19 判据是「句」，一拍含多句时会低估；宏观量级与人物位置两项未纳入代理。
       用途＝定位该人工核的铁律19 位置（脚本唯一查不到的核心硬规则就是这类内容判断）。
    H. ②段必备要件与图号一致性：
       ① 三混合配比%（三项合计 100）——规则源 90/91 号 ⚠️级保留项，"禁止误删" → 硬项
       ② 场景五层（地标=/地面=/光=/粒子=）——35 号 16.1"每场戏②段按此五层写全" → 硬项
       ③ ③段引用的 @imageN 必须②段已定义 → 硬项
       ④ 图号-实体疑似错配 → **启发式信息项**：图号后面紧跟一个不属于它的实体专名即提示，
          必须人工确认（脚本与总控都不得改写正文，改动交回执行层）
    I. 特效落实（12号 2.9.1 自动补全路由 / 铁律19 / 铁律33 / 铁律5）：逐镜检出
       ① 尺度四件套：③段是否含 画框分数 / 宏观量级词 / 参照物 / 人物占比（铁律19，缺一即废句重写）
       ② 时间手法：顿帧类 / 升格类 / 甩镜类 / 爆闪类 各是否出现
       ③ 巨物感三连：①凝聚特写 ②逼近下降 ③暴拉超远景（仅"打戏镜且标题含巨物词"时判，铁律33 缺一不可）
       ④ 爆点量级（铁律5 三档）与并行特效现象类数（12 号 2.9.1 十四大类）
       并列出"打戏镜普遍无⑨EWS再证""候选巨物镜三连不齐"作为待人工核项。
       **整段为信息项，不计入硬项/软项**——"什么算大特效镜/巨物镜"须人工判断，且铁律5 有适用边界
       （纯文戏与对话片不触发），爆点量级为 0 不等于违规。用途＝把"特效一般般"变成可定位的镜号与缺失项。

参数:
    --max15 N   >10s 镜数量上限，默认 3（每换项目都要按该项目契约给值）
    --dur N     标题缺（N秒）时的兜底项目时长（缺声明本身报硬项）
    --rules DIR 规则源 references/ 目录，默认指向已安装的 xiaojia-prompt-generator
    --no-verbatim 关闭 F 段原文覆盖率

运行环境:
    仅针对 WorkBuddy：默认路径按当前用户目录解析（~/.workbuddy/skills/...），不写死盘符与用户名。

只认 v13.1.1 四段式成稿格式:
    镜标题   ## S01｜戏剧功能词（15秒）      ← 镜号完全来自稿子自身的小节标题，脚本不重编号
    四段     **①画质基准** / **②角色·场景·核心设定** / **③时间轴** / **④负面提示词**
    拍       每拍独立成行，行首为 `00:00—00:02，`
    正向词   每镜末尾 【全局正向词】
    H 段图号映射兼容两种②段写法：新式「本镜参考图锚定：@image1＝实体」与
    旧式「本镜上传顺序：@image1实体名」，只在那一句内解析，后文用法句不得覆盖定义。
    镜标题原文另存 `title` 字段：`tag` 只保留"｜"之前的镜号，判"巨物镜"须用 `title`。

版本:
    v3.7 2026-09-16  新增 I 段「特效落实」（12号 2.9.1 / 铁律19 / 铁律33 / 铁律5 的字面证据逐镜检出，
                     全部为信息项）；shots 增加 `title` 字段（此前巨物镜判定用 `tag` 恒不命中）
    v3.6 2026-09-16  适配规则源 v13.1.1：F 段打戏原文来源由 10 号改为 **11 号 2.1**（权威位置，
                     且 11 号 2.1 是普通行不是围栏块，正则改为行匹配）；E 段改为**按①段画质基准
                     分轨**——打戏镜必须绑视觉目标标签（没有即硬项），文戏镜不该有（有即软项）；
                     标签清单数字 242 → 235；A 段新增**铁律54 公式制字数预算**（分轨取每拍上限）
    v3.5 2026-09-16  新增 H 段「②段必备要件与图号一致性」（三混合配比% / 场景五层 /
                     图号可追溯，均计入硬项；图号-实体疑似错配为启发式信息项）。
                     图号映射解析兼容新旧两种②段写法，并修掉"后文用法句覆盖定义"与
                     "把形态词（兽相）当另一个实体"两个误报源
    v3.4 2026-09-16  新增 G 段「尺度四件套」代理（铁律19），逐拍给画框分数/参照物覆盖率与疑点拍
    v3.3 2026-09-15  新增 F 段「锁死画质原文覆盖率」与 --no-verbatim；默认路径改为按 ~ 解析，
                     不再硬编码盘符与用户名（只服务 WorkBuddy）
    v3.2 2026-09-15  现版。新增 E 段「运镜标签越界」与 --rules；标签清单改为
                     方括号 ∪ 「视觉目标（…）」纯文本枚举（238 → 242），
                     避免把铁律52 纯文本点名的 [压迫逼近]/[收束定场] 误判为越界
    v3.1 2026-09-15  收敛为 v13.0 单格式；新增章节级项目契约汇总与 --max15/--dur
    v3   2026-09-15  加章节级汇总；拍识别改为必须从行首开始
    v2   2026-09-15  修三个 bug：镜号正则 S0\\d 漏 S10+；硬判「拍相加==30s」；CRLF/空行导致段落读不到
    v1   2026-09-15  首版

已知同级规则冲突（照实报出，不自动豁免）:
    ①段（画质基准锁死原文）与②段（资产完整锁定）在含大型法术/法阵/法身的镜次里
    必然超出 ≤250 / ≤400，属铁律1、铁律31/4.0.4 与铁律54 的冲突，按项目裁决处理。
"""
import re
import sys
import os

Q = dict(blk1=250, blk2=400, blk4=300, beat_lo=220, beat_hi=280, max15=3)
SEC_RE = re.compile(r"(?m)^\*\*([\u2460\u2461\u2462\u2463])[^\n]*\*\*[ \t]*$")
TIME_RE = re.compile(r"(\d{1,2}):(\d{2}(?:\.\d+)?)[\u2014\u2013-](\d{1,2}):(\d{2}(?:\.\d+)?)")
BEAT_SPLIT = re.compile(r"(?m)(?=^[ \t]*\d{1,2}:\d{2}(?:\.\d+)?[\u2014\u2013-])")
CUT_TAIL = re.compile(r"(?m)^[ \t]*\u3010\u5168\u5c40\u6b63\u5411\u8bcd\u3011.*$")
STOP = "\u5168\u5c40\u6b63\u5411\u8bcd"
TAG_RE = re.compile(r"\[([^\]\n]{2,12})\]")
TAG_HINT = ("\u8ddf", "\u5c55", "\u805a\u7126")  # 跟*/展*/聚焦*：可生成前缀，越界即计入硬项
TAG_FAMILY = ("\u8ddf", "\u5c55", "\u805a\u7126", "\u538b\u8feb", "\u6536\u675f", "\u53cd\u9988",
              "\u5de8\u7269", "\u7a92\u606f", "\u627e", "\u8f6c\u573a")  # 运镜目标族（用于计数展示）
HOME = os.path.expanduser("~")
RULES_DEFAULT = os.path.join(HOME, ".workbuddy", "skills", "xiaojia-prompt-generator", "references")
# G 段：铁律19 尺度四件套（偏宽代理，只查字面证据，供定位用）
SCALE_RE = re.compile(r"占[^\uff0c\u3002\uff1b\u3001]{0,10}(\u6210|\u5e45|\u534a)|\u5360\u6bd4|\u5343\u5206\u4e4b\u4e00|\u6781\u5c0f\u6bd4\u4f8b")
REF_RE = re.compile(r"\u53cd\u886c|\u53c2\u7167|\u5982\u5fae\u5c18|\u4eba\u5f62|\u5343\u5206\u4e4b\u4e00|\u4e0d\u8db3[^\uff0c\u3002\uff1b]{0,6}\u5206\u4e4b\u4e00")
FX_RE = re.compile(r"\u7206|\u70b8|\u51b2\u51fb|\u8d2f\u7a7f|\u8f70|\u65a9|\u5288|\u788e\u88c2|\u5d29\u89e3|\u7194|"
                   r"\u706b|\u5149\u67f1|\u5203|\u5251\u6c14|\u9707|\u788e\u5c51|\u6c14\u6d6a|\u6f29\u6da1|\u6dc0\u6f2a|\u707c")
# H 段：②段必备要件（三混合配比 / 场景五层）与图号一致性
IMG_MAP_RE = re.compile(r"@image(\d+)\s*[\uff1d=:：]\s*([^\uff0c,\uff1b;\u3002\n]{1,40})")
IMG_REF_RE = re.compile(r"@image\d+")
PCT_TOTAL_RE = re.compile(r"\u5408\u8ba1\s*100\s*%")
B2_LAYERS = ("\u5730\u6807=", "\u5730\u9762=", "\u5149=", "\u7c92\u5b50=")  # 地标= 地面= 光= 粒子=
TOKEN_SPLIT = re.compile(r"[\u00b7\uff0b+&\u3001\u4e0e\u548c\uff0f/]")
SCENE_HINT = ("\u72b6\u6001", "\u573a\u666f", "\u6218\u573a", "\u7a7a\u57df", "\u4e91\u6d77", "\u4f59\u6ce2", "\u5b8c\u6574")
TOKEN_STOP = ("\u53c2\u8003\u56fe", "\u4e25\u683c", "\u540c\u4e0a")


def parse_img_map(b2):
    """解析②段的 @imageN→实体 映射，兼容两种写法：
       新式  「本镜参考图锚定：@image1＝实体，…」
       旧式  「本镜上传顺序：@image1实体名，…」
    只在"上传顺序/参考图锚定"那一句内解析，避免把③式用法（@imageN在…)误当定义。"""
    if not b2:
        return {}
    m = re.search(r"(?:\u672c\u955c\u4e0a\u4f20\u987a\u5e8f|\u672c\u955c\u53c2\u8003\u56fe\u951a\u5b9a)[^\n]*?[\uff1a:]\s*([^\u3002\uff1b\n]*)", b2)
    seg = m.group(1) if m else ""
    if not seg:
        return {}
    out = {}
    for mm in re.finditer(r"@image(\d+)\s*[\uff1d=:\uff1a]?\s*([^\uff0c,\uff1b;\u3002\u3001\n]{2,40})", seg):
        ent = re.split(r"(?=@image)", mm.group(2))[0].strip()
        if ent:
            out.setdefault("@image%d" % int(mm.group(1)), ent)  # 首次出现即定义，后文用法句不得覆盖
    return out


def entity_tokens(phrase):
    """把②段 @imageN 映射值切成实体词，用于图号-实体错配的启发式比对。"""
    out = []
    for tok in TOKEN_SPLIT.split(phrase or ""):
        tok = tok.strip()
        if len(tok) < 2 or any(h in tok for h in SCENE_HINT) or any(h in tok for h in TOKEN_STOP):
            continue
        for pre in ("\u6c88\u9752\u68a7", "\u91d1\u9762\u8230\u4e3b", "\u4e07\u8c61\u9e3f", "\u4e91\u5bab\u5251",
                    "\u5c71\u6cb3\u5730\u5951", "\u5341\u4e8c\u5149\u8f6e", "\u54aa\u54aa", "\u8230\u4e3b"):
            # 只收"实体专名"：形态词（兽相/虚影/状态）不算另一个实体，否则会大量误报
            if pre in tok and pre not in out:
                out.append(pre)
    return out

# F 段：锁死画质原文来源（打戏 11 号 2.1 整行 / 文戏 20 号 3.1 中文版段）
# v13.1.1：打戏画质基准的**权威位置由 10 号改为 11 号 2.1**（100 号 21.0.0 第 11 条：
# "一切『10 号 2.1』字样为历史误引，一律按 11 号 2.1 解析"）。11 号 2.1 的画质词是加粗标题
# 下的整行正文、不是围栏代码块，故改用行匹配（取首个 UE5.5 开头的行即 2.1 正文）。
VERBATIM_SRC = [
    ("11-打戏B-特效位移拖尾.md", "打戏 11号2.1", r"(?m)^UE5\.5 Path Tracing.*$", 0),
    ("20-文戏规则组.md", "文戏 20号3.1", r"(?m)^高精度3D半写实国漫BJD人偶风.*$", 0),
]
# 画质分轨标志（读①段）：决定该镜走打戏还是文戏规则组，E 段与 A 段字数预算都靠它
KIND_ACTION = "Path Tracing"      # 打戏画质基准（11 号 2.1）
KIND_DRAMA = "BJD人偶风"           # 文戏画质基准（20 号 3.1）

# ---------------------------------------------------------------------------
# I 段：特效落实（规则源 12号 2.9.1 六要素/自动补全路由 · 铁律19 · 铁律33 · 铁律5）
# 全部为「字面证据检出」，只用于定位该人工核的位置，不作通过/否决；
# 例外：巨物镜缺三连、大特效镜无 ⑨EWS再证 → 列软项提示（铁律原文为"缺项即补""缺一不可"）。
# ---------------------------------------------------------------------------
MAG_RE = re.compile(r"上百米|数百米|数公里|数十丈|百丈|千丈|万丈|数十里|数里|铺天|遮天|笼罩天地|上千|上万|千军|成百|山岳")
PPL_RE = re.compile(r"千分之一|1/2000|两千分之一|三千分之一|极小一点|如一粒尘|如微尘|微尘|如蚁|光点|蚂蚁|黑点")
EWS_RE = re.compile(r"EWS|大远景|暴拉|阶梯(?:式)?拉远|持续拉远|层递拉远|急拉远")
CTX_RE = re.compile(r"入画|冲出(?:上|下|左|右)?画框|贯穿上下|撑满|出血|贴地炸开|没入云海|碰到画框|超出画框")
TIME_WORDS = (("顿帧", re.compile(r"顿帧|极短一顿|悬停|极短的一顿")),
              ("升格", re.compile(r"升格|微微放慢|旋即爆速|短暂停顿|放慢半拍")),
              ("甩镜", re.compile(r"甩镜|Whip|急摇|甩到")),
              ("爆闪", re.compile(r"爆闪|糊镜|爆光吞|强光吞|白闪")))
IMPACT_WORDS = (("轻爆", re.compile(r"强光一闪|尘浪|碎屑弹起|镜头轻震|轻震")),
                ("重爆", re.compile(r"雾化成球|环形冲击波|犁出浅坑|被撞后挫|往外鼓|冲击环|贴地推开")),
                ("核爆", re.compile(r"能量柱|蘑菇头|强光吞没|巨坑|蘑菇云|擎天|拔地而起")))
GIANT_TRIPLE = (("①凝聚特写", re.compile(r"纹路|内部构造|流动|符文|鳞|纹理|结构|契纹|冰晶|铸造")),
                ("②逼近下降", re.compile(r"切开云层|音爆|风压掀飞|压成白色|掀飞|空气被压|压弯|扑面而来|下压")),
                ("③暴拉超远景", re.compile(r"遮天蔽日|蚁群|黑蚁|暴拉|超远景|千军")))
GIANT_SHOT_RE = re.compile(r"巨兽|巨物|天柱|法相|巨像|万丈|千丈|巨型|巨剑|山岳|遮天|擎天")
FXCLS = {
    "物理破坏": r"碎石|岩块|碎片|碎屑|砖瓦|尘粉|龟裂|崩碎",
    "流体": r"水浪|水雾|浪墙|海啸|浪线|岩浆|泥浆|墨汁|白浪|浪头",
    "火焰高温": r"火焰|火柱|火环|火舌|热浪|白热|黑烟|余烬|赤金火",
    "冰霜低温": r"冰晶|霜|寒气|冰柱|冻",
    "雷电电磁": r"电弧|落雷|电蛇|雷痕",
    "气态大气": r"音爆云|龙卷|罡风|气浪|风压|浓雾|蒸汽|云絮",
    "光效辐射": r"光柱|光尘|光羽|强光|光刃|爆光|流光",
    "空间效应": r"冲击波|空间扭曲|裂纹|扭曲|螺旋",
    "拖尾轨迹": r"拖尾|残影|拖出|光带|长虹",
    "帧特效": r"残影|重影|速度线|动态模糊|抽帧",
    "粒子系统": r"火星|光点|灰烬|沙粒|盐粒|光粒|星屑",
    "烟尘": r"尘浪|尘柱|尘环|尘幕|烟尘|扬尘|尘雾|烟柱",
}
FXCLS_RE = {k: re.compile(v) for k, v in FXCLS.items()}


def load_legal_tags(rules_dir):
    """合法标签 = 规则源里出现过的方括号标签 ∪ '视觉目标（…）' 里纯文本枚举的核心目标。

    铁律52 的 8 个核心目标在 00 号里是以「视觉目标（展规模/跟轨迹/…）」纯文本形式写的，
    没有方括号；只扫方括号会把它们误判为越界，故一并并入。
    """
    if not rules_dir or not os.path.isdir(rules_dir):
        return None
    tags = set()
    for fn in os.listdir(rules_dir):
        if not fn.endswith(".md"):
            continue
        try:
            txt = open(os.path.join(rules_dir, fn), encoding="utf-8").read()
        except Exception:
            continue
        tags |= set(TAG_RE.findall(txt))
        for m in re.finditer(r"\u89c6\u89c9\u76ee\u6807\uff08([^\uff09]{4,60})\uff09", txt):
            for tok in re.split(r"[/\uff0f]", m.group(1)):
                tok = tok.strip()
                if 2 <= len(tok) <= 8:
                    tags.add(tok)
    return tags


def probes_of(text):
    """把锁死原文切成特征表述。

    三类内容必须先剔掉，否则会把「按规则不该出现在正文里的东西」算成"未命中"：
      1. Time Ramp 内部参数档位（如「基础24fps 1/48s，命中升格48-120fps」）——铁律要求工程参数零泄漏；
      2. 🔴 之后的落稿指令（如「落稿压成2-3句连贯话、正文不分号罗列长清单」）——是对写作者的话，不是画面词；
      3. [占位符] 内容（如 [环境主色]/[5219按题材选]）——由当次画面填充，不可能字面命中。
    其余按非字词字符切分，保留 ≥2 汉字或 ≥4 拉丁字符的 token。
    """
    t = re.sub(r"[\uff08(][^\uff09)]*fps[^\uff09)]*[\uff09)]", "", text)
    t = re.split("\U0001f534", t)[0] if "\U0001f534" in t else t
    t = re.sub(r"\[[^\]]*\]", "", t)
    out, seen = [], set()
    for tok in re.split(r"[^\w\u4e00-\u9fff]+", t):
        if not tok:
            continue
        cjk = len(re.findall(r"[\u4e00-\u9fff]", tok))
        if (cjk >= 2 or len(tok) >= 4) and tok not in seen:
            seen.add(tok)
            out.append(tok)
    return out


def load_verbatim_sources(rules_dir):
    """取出规则源里的锁死画质原文块，返回 [(文件名, 标签, 特征表述列表)]。"""
    res = []
    for fn, label, pat, flag in VERBATIM_SRC:
        fp = os.path.join(rules_dir or "", fn)
        if not os.path.isfile(fp):
            continue
        try:
            txt = open(fp, encoding="utf-8").read()
        except Exception:
            continue
        m = re.search(pat, txt, flag) if flag else re.search(pat, txt)
        if not m:
            continue
        pr = probes_of(m.group(1) if m.groups() else m.group(0))
        if pr:
            res.append((fn, label, pr))
    return res


def first_section(body):
    """取 ①段（画质基准）正文。"""
    m1 = re.search(r"(?m)^\*\*\u2460[^\n]*\*\*[ \t]*$", body)
    m2 = re.search(r"(?m)^\*\*\u2461[^\n]*\*\*[ \t]*$", body)
    return body[m1.end():m2.start()] if (m1 and m2) else ""


def n(s):
    return len(re.sub(r"\s", "", s or ""))


def sections(body):
    """按 v13.0 的 **①** — **④** 标记切四段；末段截到【全局正向词】为止。"""
    marks = list(SEC_RE.finditer(body))
    out = {}
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        seg = body[m.end():end]
        cut = CUT_TAIL.search(seg)
        if cut:
            seg = seg[:cut.start()]
        out[m.group(1)] = seg.strip("\n")
    return out


def declared_seconds(header):
    m = re.search(r"[\uff08(](\d+)\s*[\u79d2s]", header)
    return int(m.group(1)) if m else None


def span_seconds(txt):
    tot, spans = 0.0, []
    for sh, sm, eh, em in TIME_RE.findall(txt or ""):
        a, b = int(sh) * 60 + float(sm), int(eh) * 60 + float(em)
        spans.append((a, b))
        tot += b - a
    return tot, spans


def check(path, max15, fallback_dur, legal=None, verbatim=True, rules=None):
    raw = open(path, encoding="utf-8-sig").read().replace("\r\n", "\n").replace("\r", "\n")
    segs = re.split(r"^##\s*(S\d{2,3}[^\n]*)$", raw, flags=re.M)
    shots, hard, soft = [], [], []

    for i in range(1, len(segs), 2):
        header, body = segs[i], segs[i + 1]
        tag = re.sub(r"\s*[\uff08(]\d+\s*\u79d2[\uff09)]", "",
                     header.split("\uff5c")[0]).strip()
        decl = declared_seconds(header) or fallback_dur
        sec = sections(body)
        b1, b2, b3, b4 = (sec.get(m) for m in "\u2460\u2461\u2462\u2463")
        l1, l2, l4 = n(b1), n(b2), n(b4)
        beats = [x for x in BEAT_SPLIT.split(b3 or "") if x.strip()]
        lens = [n(x) for x in beats]
        tot, spans = span_seconds(b3)
        shot_words = l1 + l2 + n(b3) + l4

        flags = []
        if decl is None:
            hard.append("%s 标题缺（N秒）声明，无法校验拍相加" % tag)
            flags.append("缺时长声明")
        elif spans and abs(tot - decl) > 0.05:
            hard.append("%s 拍相加=%.1fs != 声明 %ds" % (tag, tot, decl))
            flags.append("拍和!=声明")
        off = [(k + 1, L) for k, L in enumerate(lens) if not (Q["beat_lo"] <= L <= Q["beat_hi"])]
        if off:
            flags.append("拍长出区x%d" % len(off))
        if l1 > Q["blk1"]:
            soft.append("%s \u2460\u6bb5 %d\u5b57 > %d" % (tag, l1, Q["blk1"]))
        if l2 > Q["blk2"]:
            soft.append("%s \u2461\u6bb5 %d\u5b57 > %d" % (tag, l2, Q["blk2"]))
        if l4 > Q["blk4"]:
            hard.append("%s \u2463\u6bb5 %d\u5b57 > %d" % (tag, l4, Q["blk4"]))
            flags.append("\u2463\u8d85\u9650")
        if l1 <= 0 or l2 <= 0 or not b3:
            hard.append("%s \u56db\u6bb5\u5f0f\u7f3a\u5931\u6216\u4e0d\u53ef\u8bfb" % tag)
            flags.append("\u7ed3\u6784\u5f02\u5e38")

        offtags = [tg for tg in TAG_RE.findall(b3 or "") if legal is not None and tg not in legal]
        # 画质分轨（读①段）+ ③段视觉目标标签（E 段判"打戏必绑、文戏不该有"）
        kind = (KIND_ACTION if KIND_ACTION in (b1 or "")
                else KIND_DRAMA if KIND_DRAMA in (b1 or "") else None)
        mv_tags = [tg for tg in TAG_RE.findall(b3 or "") if tg.startswith(TAG_FAMILY)]

        # H：②段必备要件 + 图号一致性
        b2txt = b2 or ""
        b3txt = b3 or ""
        b2map = parse_img_map(b2txt)
        b2pct = [int(x) for x in re.findall(r"(\d+)\s*%", PCT_TOTAL_RE.sub("", b2txt))]
        layers = [k for k in B2_LAYERS if k in b2txt]
        b3imgs = sorted({x for x in IMG_REF_RE.findall(b3txt)}, key=lambda x: int(x[6:]))
        undef = [x for x in b3imgs if x not in b2map]
        has_fx = bool(FX_RE.search(b3txt))
        mism = []  # 图号-实体疑似错配：需全部镜解析完、拿到全章实体词表后再判（见下方后处理）
        if has_fx and len(b2pct) < 3:
            hard.append("%s \u2461\u6bb5\u7f3a\u4e09\u6df7\u5408\u914d\u6bd4\uff08\u5f53\u955c\u542b\u7279\u6548\uff0c\u4ec5\u67e5\u5230 %d \u9879\uff09"
                        % (tag, len(b2pct)))
            flags.append("\u7f3a\u4e09\u6df7\u5408")
        elif has_fx and sum(b2pct[:3]) != 100:
            hard.append("%s \u2461\u6bb5\u4e09\u6df7\u5408\u914d\u6bd4\u5408\u8ba1=%d%%\uff08\u5e94 100%%\uff09" % (tag, sum(b2pct[:3])))
            flags.append("\u914d\u6bd4\u5408\u8ba1\u5f02\u5e38")
        if len(layers) < 4:
            hard.append("%s \u2461\u6bb5\u573a\u666f\u4e94\u5c42\u7f3a\u9879\uff1a%s\uff08\u5e94\u5730\u6807=/\u5730\u9762=/\u5149=/\u7c92\u5b50= \u56db\u9879\u5168\uff09"
                        % (tag, "\u3001".join(k for k in B2_LAYERS if k not in layers)))
            flags.append("\u7f3a\u4e94\u5c42")
        if undef:
            hard.append("%s \u2462\u6bb5\u5f15\u7528\u4e86\u2461\u6bb5\u672a\u5b9a\u4e49\u7684\u56fe\u53f7\uff1a%s" % (tag, ", ".join(undef)))
            flags.append("\u56fe\u53f7\u672a\u5b9a\u4e49")

        shots.append(dict(tag=tag, title=header, decl=decl, spans=len(spans), tot=tot, l1=l1, l2=l2, l3=n(b3),
                          l4=l4, words=shot_words, lens=lens, flags=flags, off=off, body=body,
                          offtags=offtags, beat_texts=beats, b2pct=b2pct, layers=layers,
                          b2map=b2map, b3imgs=b3imgs, undef=undef, mism=mism, has_fx=has_fx,
                          kind=kind, mv_tags=mv_tags))

    # 后处理：全章实体词表 → 图号-实体疑似错配（启发式：图号紧跟一个不属于该图号的实体名）
    chapter_lex = set()
    for s in shots:
        for v in s["b2map"].values():
            chapter_lex |= set(entity_tokens(v))
    for s in shots:
        body3 = s["body"]
        pos = body3.find("\u2462")
        if pos >= 0:
            body3 = body3[pos:]
        own = set()
        for v in s["b2map"].values():
            own |= set(entity_tokens(v))
        seen = set()
        for mm in IMG_REF_RE.finditer(body3):
            own_here = set(entity_tokens(s["b2map"].get(mm.group(0), "")))
            after = body3[mm.end():mm.end() + 3]
            for tok in sorted(chapter_lex - own_here):
                if tok in after and (mm.group(0), tok) not in seen:
                    seen.add((mm.group(0), tok))
                    s["mism"].append((mm.group(0), tok, s["b2map"].get(mm.group(0), ""), after))

    print("=" * 78)
    print("file    :", path)
    print("bytes   :", os.path.getsize(path), "| shots:", len(shots))
    print()
    print("--- A. 章节级 ---")
    total_s = sum(s["tot"] for s in shots)
    dist = {}
    for s in shots:
        dist[s["decl"]] = dist.get(s["decl"], 0) + 1
    over10 = [s["tag"] for s in shots if (s["decl"] or 0) > 10]
    print("  镜数        : %d" % len(shots))
    print("  总时长      : %ss" % (int(total_s) if abs(total_s - int(total_s)) < 0.05 else round(total_s, 1)))
    print("  时长分布    : " + ", ".join("%ss x%d" % (k, v) for k, v in
                                        sorted(dist.items(), key=lambda x: (x[0] is None, x[0] or 0))))
    print("  >10s 镜     : %d 个 %s（上限 %d）%s" % (len(over10), over10, max15,
                                                "  <-- 超上限" if len(over10) > max15 else " OK"))
    if len(over10) > max15:
        hard.append(">10s 镜 %d 个 > 上限 %d" % (len(over10), max15))
    tw = sum(s["words"] for s in shots)
    print("  全稿总字数  : %d" % tw)
    # 铁律54（v13.1.1 公式制）单镜预算 = ①250 + ②400 + ③每拍上限×实际拍数 + ④300 + ⑤正向词100
    # ③每拍上限：打戏 280（220-280）/ 文戏 240（180-240）；分轨读①段画质基准
    cap_th = cap_adj = 0
    for s in shots:
        hi = Q["beat_hi"] if s["kind"] != KIND_DRAMA else 240
        nb = max(1, s["spans"])
        cap_th += Q["blk1"] + Q["blk2"] + hi * nb + Q["blk4"] + 100
        cap_adj += s["l1"] + s["l2"] + hi * nb + Q["blk4"] + 100
    mark = "OK" if tw <= cap_adj else "超出 %d 字" % (tw - cap_adj)
    print("  字数预算    : 理论上限 %d 字 ｜ ①②按实测计入后 %d 字 ｜ 实测 %d 字  %s"
          % (cap_th, cap_adj, tw, mark))
    print("                （①/②段属已知同级规则冲突，理论值必然被突破；比第二列才有意义）")
    print()
    print("--- B/C. 逐镜 ---")
    print("%-6s%5s%5s%6s%6s%6s%6s%8s  %-30s %s" % ("\u955c", "\u58f0\u660e", "\u62cd", "\u62cd\u548c",
                                                   "\u2460", "\u2461", "\u2463", "\u5168\u955c\u5b57",
                                                   "\u62cd\u957f", "\u8bc1\u636e\u9879"))
    for s in shots:
        ev = "img%d recap%d frame%d cut%d" % (s["body"].count("@image"),
                                              s["body"].count("\u4e0a\u4e00\u955c\u5c3e\u5e27\u590d\u8ff0"),
                                              s["body"].count("\u5360\u753b\u6846"),
                                              s["body"].count("\u9690\u5f62\u526a\u8f91\u70b9"))
        bl = [int(x) if abs(x - int(x)) < 0.05 else round(x, 1) for x in s["lens"]]
        print("%-6s%5s%5d%6d%6d%6d%6d%8d  %-30s %s%s" % (s["tag"], s["decl"], s["spans"], int(round(s["tot"])),
                                                       s["l1"], s["l2"], s["l4"], s["words"], str(bl), ev,
                                                       ("  " + ",".join(s["flags"])) if s["flags"] else ""))
    print()
    print("--- 结构完整性 ---")
    for label, pat in (("headers", r"^##\s*S\d{2,3}"), ("\u2460\u753b\u8d28\u57fa\u51c6", r"(?m)^\*\*\u2460"),
                       ("\u2461\u8bbe\u5b9a", r"(?m)^\*\*\u2461"), ("\u2462\u65f6\u95f4\u8f74", r"(?m)^\*\*\u2462"),
                       ("\u2463\u8d1f\u9762", r"(?m)^\*\*\u2463"),
                       (STOP, r"\u3010\u5168\u5c40\u6b63\u5411\u8bcd\u3011")):
        print("  %-10s %d" % (label, len(re.findall(pat, raw, re.M))))
    print()
    print("--- E. 运镜标签与画质分轨（铁律52 视觉目标）---")
    if legal is None:
        print("  skipped: 未加载规则源（用 --rules 指定 references 目录）")
    else:
        mv_legal = sorted(t for t in legal if t.startswith(TAG_FAMILY))
        print("  规则源标签三层：铁律52 明列核心目标 8 个 ｜ 运镜目标族 %d 个 ｜ 全源方括号 %d 个"
              % (len(mv_legal), len(legal)))
        print("  核心 8：展规模/跟轨迹/聚焦命中/跟爆发/展结果/聚焦细节/压迫逼近/收束定场")
        print("  判据：铁律52「每个运镜必须绑一个视觉目标…写不出目标=凑数运镜、删」；70 号质检查的是"
              "「有没有绑目标」，不是「逐字命中 8 词」。本段为**偏严的机器代理**：要求用词在规则源里出现过。")
        off_all = {}
        for s in shots:
            for tg in s["offtags"]:
                off_all.setdefault(tg, []).append(s["tag"])
        if not off_all:
            print("  越界标签：none")
        else:
            for tg in sorted(off_all):
                mark = "  <-- 形如视觉目标，须改用规则清单用词" if tg.startswith(TAG_HINT) \
                    else "  (非运镜标签，自行判断是否属于合法结构标记)"
                print("  [%s] x%d  \u955c\uff1a%s%s" % (tg, len(off_all[tg]), ",".join(off_all[tg]), mark))
            for tg, where in off_all.items():
                if tg.startswith(TAG_HINT):
                    hard.append("\u8fd0\u955c\u6807\u7b7e [%s] \u4e0d\u5728\u89c4\u5219\u6e90\u6e05\u5355\u5185\uff08%s\uff09" % (tg, ",".join(where)))
        # 画质分轨判定：打戏镜必须绑视觉目标（铁律0.5 L99/L100、铁律20 L270、铁律52）；
        # 文戏镜不该有（20 号标杆示例明文"不贴标签"，文戏走"运镜融合句式"）
        n_act = sum(1 for s in shots if s["kind"] == KIND_ACTION)
        n_dra = sum(1 for s in shots if s["kind"] == KIND_DRAMA)
        print("  画质分轨    : 打戏 %d 镜 ｜ 文戏 %d 镜 ｜ 未识别 %d 镜"
              % (n_act, n_dra, len(shots) - n_act - n_dra))
        no_mv = [s["tag"] for s in shots if s["kind"] == KIND_ACTION and not s["mv_tags"]]
        bad_mv = [s["tag"] for s in shots if s["kind"] == KIND_DRAMA and s["mv_tags"]]
        if no_mv:
            print("  打戏镜未绑视觉目标：%s  <-- 硬项" % ",".join(no_mv))
            for t in no_mv:
                hard.append("%s 打戏镜③段无视觉目标标签（铁律52 漏绑视觉目标）" % t)
        if bad_mv:
            print("  文戏镜含视觉目标标签：%s  <-- 软项提示" % ",".join(bad_mv))
            for t in bad_mv:
                soft.append("%s 文戏镜③段含视觉目标标签（20 号口径：文戏不贴标签）" % t)
    if verbatim and legal is not None:
        print()
        print("--- F. 锁死画质原文覆盖率（信息项，不做通过/否决）---")
        vsrc = load_verbatim_sources(rules)
        if not vsrc:
            print("  skipped: 规则源里未找到锁死画质原文块")
        else:
            for fn, label, pr in vsrc:
                print("  源 [%s] %s：%d 个特征表述" % (label, fn, len(pr)))
            print("  %-6s%-14s%-13s %s" % ("\u955c", "\u91c7\u7528\u6e90", "\u8986\u76d6\u7387", "\u672a\u547d\u4e2d\u7684\u7279\u5f81\u8868\u8ff0"))
            th = ta = 0
            for s in shots:
                seg = first_section(s["body"])
                if not seg:
                    continue
                best = None
                for fn, label, pr in vsrc:
                    hit = [p for p in pr if p in seg]
                    if best is None or len(hit) > best[2]:
                        best = (label, pr, len(hit), [p for p in pr if p not in seg])
                label, pr, hc, missing = best
                th += hc
                ta += len(pr)
                tail = ("\u3001".join(missing[:5]) + ("\u2026" if len(missing) > 5 else "")) if missing else "none"
                print("  %-6s%-14s%-13s %s" % (s["tag"], label, "%d/%d=%d%%" % (hc, len(pr), round(100 * hc / len(pr))), tail))
            if ta:
                print("  章节平均覆盖率: %d%%（%d/%d）" % (round(100 * th / ta), th, ta))
            print("  判读：覆盖率低（<60%）＝疑似①段不是从锁死原文派生（可能没读就编）；但规则要求"
                  "「落稿压成2-3句连贯话、正文不分号罗列长清单」，故字面未命中 ≠ 违规，需人工核语义。")
    print()
    print("--- G. 尺度四件套（铁律19；偏宽代理，信息项）---")
    all_beats = [(s["tag"], b) for s in shots for b in s.get("beat_texts", [])]
    nb = len(all_beats)
    if not nb:
        print("  skipped: 未解析到拍")
    else:
        sc = [x for x in all_beats if SCALE_RE.search(x[1])]
        rf = [x for x in all_beats if REF_RE.search(x[1])]
        bo = [x for x in all_beats if SCALE_RE.search(x[1]) and REF_RE.search(x[1])]
        fx = [x for x in all_beats if FX_RE.search(x[1])]
        fxs = [x for x in fx if SCALE_RE.search(x[1])]
        print("  铁律19：凡攻击特效/大招/法术/EWS宏观镜，一句之内四样齐全"
              "（①画框分数占比 ②宏观尺寸量级 ③参照物 ④人物在画框位置），缺一即废句重写。")
        print("  逐拍覆盖（代理只查①画框分数 与 ③参照物 两类字面证据）：")
        print("    含画框分数/成数 : %d/%d (%.0f%%)" % (len(sc), nb, 100 * len(sc) / nb))
        print("    含参照物        : %d/%d (%.0f%%)" % (len(rf), nb, 100 * len(rf) / nb))
        print("    两者都有        : %d/%d (%.0f%%)" % (len(bo), nb, 100 * len(bo) / nb))
        print("    疑似特效拍      : %d（其中含画框分数 %d 个 = %.0f%%）"
              % (len(fx), len(fxs), 100 * len(fxs) / max(1, len(fx))))
        miss = [x for x in fx if not SCALE_RE.search(x[1])]
        if miss:
            print("    疑点拍（疑似特效/宏观镜但无画框分数，交人工核该句是否为攻击特效句）：")
            for tg, b in miss[:8]:
                print("      %s %s…" % (tg, b[6:60].replace("\n", " ")))
            if len(miss) > 8:
                print("      …另有 %d 个，见完整清单需人工过闸" % (len(miss) - 8))
        print("  说明：本项按「拍」统计，铁律19 判据是「句」；一拍含多句时会低估覆盖率，"
              "且宏观量级/人物位置两项未纳入代理，故**不得作为通过或否决依据**，只用于定位疑点。")
    print()
    print("--- H. ②段必备要件与图号一致性 ---")
    ok_pct = [s["tag"] for s in shots if s["has_fx"] and len(s["b2pct"]) >= 3 and sum(s["b2pct"][:3]) == 100]
    bad_pct = [s["tag"] for s in shots
               if s["has_fx"] and not (len(s["b2pct"]) >= 3 and sum(s["b2pct"][:3]) == 100)]
    ok_lay = [s["tag"] for s in shots if len(s["layers"]) == 4]
    undef_all = {s["tag"]: s["undef"] for s in shots if s["undef"]}
    mism_all = {s["tag"]: s["mism"] for s in shots if s["mism"]}
    print("  ① 三混合配比%（铁律58 ⚠️级保留项，规则源 90/91 号明文禁止误删）")
    print("     达标 %d/%d 镜：%s" % (len(ok_pct), len(shots), ",".join(ok_pct) or "none"))
    if bad_pct:
        for s in shots:
            if s["tag"] in bad_pct:
                print("     ✗ %s 只查到 %d 项配比%s" % (s["tag"], len(s["b2pct"]),
                      "" if len(s["b2pct"]) < 3 else "、合计 %d%%" % sum(s["b2pct"][:3])))
    print("  ② 场景五层（35 号 16.1「每场戏②段按此五层写全」）")
    print("     四层齐全 %d/%d 镜：%s" % (len(ok_lay), len(shots), ",".join(ok_lay) or "none"))
    for s in shots:
        if len(s["layers"]) < 4:
            print("     ✗ %s 缺：%s" % (s["tag"], "、".join(k for k in B2_LAYERS if k not in s["layers"])))
    print("  ③ 图号可追溯（③段引用的 @imageN 必须②段已定义）")
    if not undef_all:
        print("     未定义引用：none")
    else:
        for k, v in undef_all.items():
            print("     ✗ %s 引用了②段未定义图号：%s" % (k, ", ".join(v)))
    print("  ④ 图号-实体疑似错配（**启发式，信息项，必须人工确认**）")
    if not mism_all:
        print("     无疑点")
    else:
        for k, lst in mism_all.items():
            for key, tok, mapped, after in lst:
                print("     ? %s %s 后面紧跟「%s」，但②段定义 %s＝%s" % (k, key, tok, key, (mapped or "?")[:24]))
        print("     判读：图号被用在②段映射之外的实体上。要先确认②段映射是否为该镜真实绑定，"
              "再决定改图号还是去掉图号（**不得由脚本或总控直接改写正文**）。")
    print("  说明：①②③ 为机械项（计入硬项）；④ 为启发式只提示，不计入任何通过/否决。")
    print()
    print("--- I. 特效落实（12号2.9.1 自动补全路由 / 铁律19 / 铁律33 / 铁律5；信息项，不作通过否决）---")
    act = [s for s in shots if s["kind"] == KIND_ACTION]
    print("  分轨：打戏 %d 镜 / 文戏 %d 镜（攻击特效类硬闸只适用打戏镜）" % (len(act), len(shots) - len(act)))
    print("  逐镜检出（③段时间轴字面证据；· = 未检出）")
    print("    %-6s %-4s | %-20s | %-12s | %-9s | %-10s | %s" % (
        "镜", "轨", "尺度四件套 占比/量级/参照/人占", "手法 顿/升/甩/闪", "巨物三连", "爆点量级", "并行特效类"))
    ews_shots, giant_shots, giant_ok, cls_max = [], [], [], 0
    for s in shots:
        txt = " ".join(s.get("beat_texts", [])) or ""
        mk = lambda r: "✓" if r.search(txt) else "·"
        four = "%s %s %s %s" % (mk(SCALE_RE), mk(MAG_RE), mk(REF_RE), mk(PPL_RE))
        tw = "%s/%s/%s/%s" % ("顿" if TIME_WORDS[0][1].search(txt) else "·",
                              "升" if TIME_WORDS[1][1].search(txt) else "·",
                              "甩" if TIME_WORDS[2][1].search(txt) else "·",
                              "闪" if TIME_WORDS[3][1].search(txt) else "·")
        is_giant = s["kind"] == KIND_ACTION and bool(GIANT_SHOT_RE.search(s.get("title", "")))
        g3 = "".join("✓" if r.search(txt) else "·" for _, r in GIANT_TRIPLE)
        imp = ",".join(k for k, r in IMPACT_WORDS if r.search(txt)) or "·"
        cls = [k for k, r in FXCLS_RE.items() if r.search(txt)]
        cls_max = max(cls_max, len(cls))
        print("    %-6s %-4s | %-20s | %-12s | %-9s | %-10s | %d %s" % (
            s["tag"], "打戏" if s["kind"] == KIND_ACTION else "文戏", four, tw,
            g3 if is_giant else "—", imp, len(cls), ",".join(cls[:4])))
        if s["kind"] == KIND_ACTION and EWS_RE.search(txt):
            ews_shots.append(s["tag"])
        if is_giant:
            giant_shots.append(s["tag"])
            if all(r.search(txt) for _, r in GIANT_TRIPLE):
                giant_ok.append(s["tag"])
    imp_cnt = {k: sum(1 for s in shots if r.search(" ".join(s.get("beat_texts", []))))
               for k, r in IMPACT_WORDS}
    print()
    print("  汇总（规则源原文均为硬要求，本段只报数不判定）")
    print("    铁律19⑨ EWS再证（大特效后须接一记暴拉EWS或阶梯拉远，缺项即补）：打戏镜命中 %d/%d → %s"
          % (len(ews_shots), len(act), ",".join(ews_shots) or "none"))
    print("    铁律33 巨物感三连（凝聚特写→逼近下降→暴拉超远景，缺一不可）：巨物镜 %d 个，三拍齐全 %d 个"
          % (len(giant_shots), len(giant_ok)))
    for s in shots:
        if s["tag"] in giant_shots and s["tag"] not in giant_ok:
            txt = " ".join(s.get("beat_texts", []))
            print("      ✗ %s 缺：%s" % (s["tag"], "、".join(k for k, r in GIANT_TRIPLE if not r.search(txt))))
    print("    铁律5 每击必爆·量级三档：含轻爆画面 %d 镜 / 重爆 %d 镜 / 核爆 %d 镜"
          % (imp_cnt["轻爆"], imp_cnt["重爆"], imp_cnt["核爆"]))
    print("    12号2.9.1 并行特效类：单镜检出最多 %d 类（分支C 缺省路由要求：三混合打底 + 自动补 1 个匹配补充特效）" % cls_max)
    big_fx = [s["tag"] for s in act
              if SCALE_RE.search(" ".join(s.get("beat_texts", []))) and FX_RE.search(" ".join(s.get("beat_texts", [])))]
    todo = []
    if big_fx and not ews_shots:
        todo.append("铁律19⑨ 大特效后须接一记暴拉EWS或阶梯拉远（缺项即补）：打戏镜 %s 均未检出" % ",".join(big_fx))
    if giant_shots and len(giant_ok) < len(giant_shots):
        todo.append("铁律33 巨物感三连（缺一不可）：%s" % "，".join(x for x in giant_shots if x not in giant_ok))
    print("  待人工核（本段全部为信息项，**不计入硬项/软项**——'什么算大特效镜/巨物镜'须人工判断）：")
    if todo:
        for x in todo:
            print("    ? " + x)
    else:
        print("    无疑点")
    print("  提示：本段是「字面证据检出」，不是内容判定。特效是否真写好须逐句读原文核（铁律19 尺度四件套与"
          "九要素齐全、⑨是否真的接到大特效之后、巨物三连是否真按三拍走）；全稿某项普遍为 · 时，"
          "优先怀疑该镜根本没读到对应规则子节。")
    print()
    print("--- 硬项违规（必修）---")
    print("\n".join(hard) if hard else "none")
    print("--- 软项偏差（已知同级规则冲突，按项目裁决）---")
    print("\n".join(soft) if soft else "none")
    for s in shots:
        if s["off"]:
            print("  [\u62cd\u957f\u660e\u7ec6] %s: %s" % (s["tag"], ", ".join(
                "\u7b2c%d\u62cd %d\u5b57" % (k, L) for k, L in s["off"])))
    return hard


if __name__ == "__main__":
    args = list(sys.argv[1:])
    max15, fallback, rules, verbatim = Q["max15"], None, RULES_DEFAULT, True
    if "--no-verbatim" in args:
        args.remove("--no-verbatim")
        verbatim = False
    for key in ("--max15", "--dur", "--rules"):
        if key in args:
            k = args.index(key)
            val = args[k + 1]
            del args[k:k + 2]
            if key == "--max15":
                max15 = int(val)
            elif key == "--dur":
                fallback = int(val)
            else:
                rules = val
    legal = load_legal_tags(rules)
    if legal is None:
        print("[warn] \u672a\u627e\u5230\u89c4\u5219\u6e90 references\uff1a%s\uff08\u8fd0\u955c\u6807\u7b7e\u68c0\u67e5\u5c06\u8df3\u8fc7\uff09" % rules)
    else:
        print("[info] \u89c4\u5219\u6e90\u6807\u7b7e\u6e05\u5355\uff1a%d \u4e2a\uff08%s\uff09" % (len(legal), rules))
    if not args:
        print(__doc__)
        sys.exit(2)
    rc = 0
    for p in args:
        if not os.path.exists(p):
            print("MISSING:", p)
            rc = 2
            continue
        if check(p, max15, fallback, legal, verbatim, rules):
            rc = 1
    sys.exit(rc)
