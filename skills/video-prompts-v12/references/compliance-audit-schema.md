# 正式提示词合规审计

正式提示词目录必须同时包含独立的 `video_prompt_compliance_audit.json`。这不是给用户看的提示词正文，而是总控门禁证据。每个镜头必须逐项填写，不能用全章一句话代替逐镜证据。

同目录还必须包含一个本章完整视频提示词 Markdown 文件，推荐命名为 `<章节名>_完整视频提示词_v12.6.md`。它按S编号顺序逐字收录全部单镜工作切片，是正式交付正文；单独的 `Sxx.txt` 不能替代它。

```json
{
  "schema_version": "video-prompt-compliance-audit-v1",
  "rule_version": "12.6.0",
  "shots": [
    {
      "shot_id": "S01",
      "content_type": "按control.md第3节判定的实际内容类型",
      "applicable_rules": ["00", "20", "37", "50", "70", "99"],
      "checks": {
        "screenplay_coverage": {"passed": true, "evidence": "列出本镜承接的场次、对白、动作和关键物件"},
        "p0_per_beat": {"passed": true, "evidence": "说明逐拍检查范围和发现结果"},
        "p1_per_shot": {"passed": true, "evidence": "说明状态、声音、人数、空间和内容覆盖"},
        "p2_per_scene": {"passed": true, "evidence": "说明场级闭环、环境音和成像检查"},
        "quality_baseline_exact": {"passed": true, "evidence": "指出采用的内容类型基准及逐字核对结果"},
        "timeline_v126": {"passed": true, "evidence": "逐拍核对母版铁律4：总时长、0.3至3秒范围、常规与例外、相邻不等长、单拍主目的和动作数"},
        "dialogue_voice_and_mouth": {"passed": true, "evidence": "逐句核对声线、情绪、重音、开口者和闭嘴者"},
        "continuity_and_space": {"passed": true, "evidence": "写明首拍承接、空间轴线、物理移动和尾帧交接"},
        "asset_mapping_real": {"passed": true, "evidence": "写明与scene_shot_map和asset_manifest的真实对应"},
        "negative_prompt_scope": {"passed": true, "evidence": "按母版核对数量与画面崩坏项；用户覆盖项如适用则另行注明"}
      },
      "exceptions": []
    }
  ]
}
```

镜头秒数完全服从用户当前项目要求及母版铁律4：用户指定多少秒就铺满多少秒，未指定才默认10秒。常规分拍默认1.5至2.0秒，总时长除以约1.75只用于估算，不是固定拍数门槛；单拍范围、短拍、长拍、相邻不等长、单拍戏剧目的和动作数量均直接按母版铁律4判定。`exceptions` 只记录实际采用的母版例外及其时间段，不创造新的例外分类。

本审计不参与规则解释。若审计文字、校验脚本或总控与V12.6母版出现差异，以用户当前明确要求和母版自身优先级为准，并修正审计或工具，禁止据此改写正文。

合规审计必须在生成正文后、运行结构验证前完成；审计或结构验证任一失败，就修订草稿并重跑。只有验证报告 `status=passed`，才允许把镜头文件作为正式稿登记。
