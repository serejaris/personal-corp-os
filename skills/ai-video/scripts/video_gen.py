#!/usr/bin/env python3
"""AI Video Generator and Connector CLI."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional

SUPPORTED_FORMATS = {"grok", "runway", "kling", "luma", "wan", "generic"}
DEFAULT_FORMAT = "generic"
DEFAULT_SIZE = "1280x720"
DEFAULT_SECONDS = 5


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Format and route AI video prompts across providers.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("prompt", nargs="?", default=None, help="Base user prompt or idea")
    parser.add_argument("--prompt-file", type=str, help="Path to text file containing base prompt")
    parser.add_argument("--format", choices=list(SUPPORTED_FORMATS), default=DEFAULT_FORMAT,
                        help="Target provider prompt format")
    
    parser.add_argument("--use-case", type=str, help="Target context")
    parser.add_argument("--scene", type=str, help="Location, environment, time of day, atmosphere")
    parser.add_argument("--subject", type=str, help="Main subject or character description")
    parser.add_argument("--action", type=str, help="Single clear action beat during the clip")
    parser.add_argument("--camera", type=str, help="Camera move, shot type, lens")
    parser.add_argument("--lighting", type=str, help="Lighting setup and mood")
    parser.add_argument("--palette", type=str, help="Color palette anchors")
    parser.add_argument("--timing", type=str, help="Timing or beat counts")
    parser.add_argument("--audio", type=str, help="Audio cue, sound effects, or background ambience")
    parser.add_argument("--dialogue", type=str, help="Spoken lines or dialogue block")
    parser.add_argument("--constraints", type=str, help="Positive constraints")
    parser.add_argument("--avoid", type=str, help="Negative constraints")
    
    parser.add_argument("--size", type=str, default=DEFAULT_SIZE, help="Resolution")
    parser.add_argument("--seconds", type=int, default=DEFAULT_SECONDS, help="Clip duration in seconds")
    parser.add_argument("--output", "-o", type=str, help="Path to save output prompt")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Print formatted output without live API dispatch")
    parser.add_argument("--json", action="store_true", help="Output result as JSON object")
    
    return parser.parse_args()


def build_structured_spec(args: argparse.Namespace) -> Dict[str, Any]:
    base_prompt = ""
    if args.prompt_file:
        path = Path(args.prompt_file)
        if not path.is_file():
            sys.stderr.write(f"Error: Prompt file not found: {args.prompt_file}\n")
            sys.exit(1)
        base_prompt = path.read_text(encoding="utf-8").strip()
    elif args.prompt:
        base_prompt = args.prompt.strip()

    return {
        "primary_request": base_prompt,
        "use_case": args.use_case,
        "scene": args.scene,
        "subject": args.subject,
        "action": args.action,
        "camera": args.camera,
        "lighting": args.lighting,
        "palette": args.palette,
        "timing": args.timing,
        "audio": args.audio,
        "dialogue": args.dialogue,
        "constraints": args.constraints,
        "avoid": args.avoid,
        "size": args.size,
        "seconds": args.seconds,
    }


def format_for_provider(spec: Dict[str, Any], target_format: str) -> str:
    primary = spec.get("primary_request") or ""
    scene = spec.get("scene")
    subject = spec.get("subject")
    action = spec.get("action")
    camera = spec.get("camera")
    lighting = spec.get("lighting")
    palette = spec.get("palette")
    timing = spec.get("timing")
    audio = spec.get("audio")
    dialogue = spec.get("dialogue")
    constraints = spec.get("constraints")
    avoid = spec.get("avoid")

    if target_format == "grok":
        lines = []
        if primary:
            lines.append(primary)
        if scene:
            lines.append(f"Scene: {scene}")
        if subject:
            lines.append(f"Subject: {subject}")
        if action:
            lines.append(f"Action: {action}")
        if camera:
            lines.append(f"Camera: {camera}")
        if lighting:
            lines.append(f"Lighting & Mood: {lighting}")
        if palette:
            lines.append(f"Color Palette: {palette}")
        if timing:
            lines.append(f"Timing: {timing}")
        if audio:
            lines.append(f"Audio: {audio}")
        if dialogue:
            lines.append(f"Dialogue: {dialogue}")
        if constraints:
            lines.append(f"Style: {constraints}")
        if avoid:
            lines.append(f"Avoid: {avoid}")
        return "\n".join(lines)

    if target_format == "runway":
        parts = []
        if camera:
            parts.append(f"{camera}.")
        if primary:
            parts.append(primary)
        if subject and action:
            parts.append(f"{subject} {action}.")
        elif action:
            parts.append(f"{action}.")
        if scene:
            parts.append(f"Set in {scene}.")
        if lighting:
            parts.append(f"{lighting}.")
        if palette:
            parts.append(f"Color tones: {palette}.")
        if avoid:
            parts.append(f"--no {avoid}")
        return " ".join(parts)

    if target_format == "luma":
        parts = []
        if camera:
            parts.append(f"[{camera}]")
        if primary:
            parts.append(primary)
        desc = []
        if subject:
            desc.append(f"featuring {subject}")
        if action:
            desc.append(f"performing {action}")
        if scene:
            desc.append(f"in {scene}")
        if desc:
            parts.append(", ".join(desc) + ".")
        if lighting:
            parts.append(f"Lighting: {lighting}.")
        return " ".join(parts)

    if target_format in ("kling", "wan"):
        lines = []
        if primary:
            lines.append(primary)
        descriptors = []
        if subject:
            descriptors.append(f"Subject: {subject}")
        if action:
            descriptors.append(f"Motion: {action}")
        if scene:
            descriptors.append(f"Environment: {scene}")
        if camera:
            descriptors.append(f"Cinematography: {camera}")
        if lighting:
            descriptors.append(f"Lighting: {lighting}")
        if palette:
            descriptors.append(f"Palette: {palette}")
        lines.extend(descriptors)
        if avoid:
            lines.append(f"Negative: {avoid}")
        return "\n".join(lines)

    lines = []
    if spec.get("use_case"):
        lines.append(f"Use case: {spec['use_case']}")
    if primary:
        lines.append(f"Primary request: {primary}")
    if scene:
        lines.append(f"Scene/background: {scene}")
    if subject:
        lines.append(f"Subject: {subject}")
    if action:
        lines.append(f"Action: {action}")
    if camera:
        lines.append(f"Camera: {camera}")
    if lighting:
        lines.append(f"Lighting/mood: {lighting}")
    if palette:
        lines.append(f"Color palette: {palette}")
    if timing:
        lines.append(f"Timing/beats: {timing}")
    if audio:
        lines.append(f"Audio: {audio}")
    if dialogue:
        lines.append(f"Dialogue: {dialogue}")
    if constraints:
        lines.append(f"Constraints: {constraints}")
    if avoid:
        lines.append(f"Avoid: {avoid}")
    return "\n".join(lines)


def main() -> None:
    args = _parse_args()
    spec = build_structured_spec(args)
    formatted_prompt = format_for_provider(spec, args.format)

    output_payload = {
        "provider_format": args.format,
        "seconds": spec["seconds"],
        "size": spec["size"],
        "formatted_prompt": formatted_prompt,
        "spec": {k: v for k, v in spec.items() if v is not None},
    }

    if args.json:
        result_text = json.dumps(output_payload, indent=2, ensure_ascii=False)
    else:
        result_text = (
            f"=== AI Video Prompt ({args.format.upper()}) ===\n"
            f"Duration: {spec['seconds']}s | Resolution: {spec['size']}\n"
            f"---------------------------------------------------\n"
            f"{formatted_prompt}\n"
            f"---------------------------------------------------"
        )

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(result_text, encoding="utf-8")
        print(f"Saved prompt specification to {args.output}")
    else:
        print(result_text)


if __name__ == "__main__":
    main()
