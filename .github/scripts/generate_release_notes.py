#!/usr/bin/env python3
"""
Generate Google Play Store release notes (What's New) using Gemini AI or local commit history fallback.
Stores outputs in android/fastlane/metadata/android/{locale}/changelogs/
"""

import os
import sys
import re
import json
import urllib.request
import urllib.error
import subprocess

def get_recent_commits(limit=10):
    try:
        output = subprocess.check_output(
            ["git", "log", f"-n{limit}", "--pretty=format:%s"],
            text=True
        )
        return [line.strip() for line in output.strip().split("\n") if line.strip()]
    except Exception as e:
        print(f"Failed to get git commits: {e}")
        return []

def get_release_notes_md():
    path = "RELEASE_NOTES.md"
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception:
            pass
    return ""

def generate_notes_with_gemini(api_key, commits, md_content):
    url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    prompt = f"""당신은 모바일 앱 '이거 먹자!' (ReviewAI)의 앱스토어 릴리즈 매니저입니다.
최근 커밋 및 변경 내역을 바탕으로, Google Play Store의 '새로운 기능 (What's New / 출시 노트)'에 들어갈
한국어(ko)와 영어(en) 텍스트를 작성해주세요.

[최근 커밋 내역]
{chr(10).join(commits)}

[RELEASE_NOTES.md 참고]
{md_content[:1500]}

[필수 규칙]
1. Play Console 500자 제한을 넘지 않도록 각 언어별 400자 이내로 간결하게 작성하세요.
2. 불릿 포인트(•) 형식의 3~4개 줄로 구성하세요.
3. 기술적/내부적 용어(PR 번호, merge, CI/CD, lint, unmount 등)는 일반 사용자가 알기 쉬운 표현('안정성 향상', '사용자 경험 개선' 등)으로 순화하세요.
4. 반드시 유효한 JSON 형식으로만 응답하세요.
JSON 스키마:
{{
  "ko": "• 한국어 내용\\n• 한국어 내용...",
  "en": "• English text\\n• English text..."
}}
"""

    req_body = {
        "contents": [
            {
                "parts": [{"text": prompt}]
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json"
        }
    }

    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(req_body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "x-goog-api-key": api_key,
            }
        )
        with urllib.request.urlopen(req, timeout=15) as response:
            result = json.loads(response.read().decode("utf-8"))
            candidate = result["candidates"][0]["content"]["parts"][0]["text"]
            parsed = json.loads(candidate)
            if "ko" in parsed and "en" in parsed:
                return parsed["ko"], parsed["en"]
    except Exception as e:
        print(f"Gemini API request failed ({type(e).__name__}); using fallback.")
    
    return None, None

def generate_fallback_notes(commits, md_content):
    ko_lines = []
    en_lines = []

    # 1. Parse from RELEASE_NOTES.md section titles (### 1. ..., ### 2. ...)
    if md_content:
        for line in md_content.splitlines():
            line_s = line.strip()
            # Match '### 1. 🤖 최신 차세대 AI 모델 도입 ...'
            if re.match(r"^###\s+\d+\.\s+", line_s):
                title = re.sub(r"^###\s+\d+\.\s+", "", line_s)
                # Remove emojis for cleaner text if needed, or keep them
                if title and len(ko_lines) < 4:
                    ko_lines.append(f"• {title}")

    # 2. Fallback to Conventional Commits
    if not ko_lines:
        for c in commits:
            if c.startswith("feat"):
                msg = c.split(":", 1)[-1].strip()
                ko_lines.append(f"• 새로운 기능: {msg}")
            elif c.startswith("fix"):
                msg = c.split(":", 1)[-1].strip()
                ko_lines.append(f"• 개선 사항: {msg}")
            if len(ko_lines) >= 4:
                break

    # 3. Default fallback
    if not ko_lines:
        ko_lines = [
            "• 최신 차세대 AI 모델(Gemini 3.5) 적용으로 리뷰 생성 속도 향상",
            "• 실시간 날씨 기반 맞춤 음식 추천 기능 안정화",
            "• 앱 성능 최적화 및 보안 강화",
            "• 알려진 버그 수정 및 사용성 개선"
        ]

    en_lines = [
        "• Enhanced AI review generation with Gemini 3.5 Flash-Lite",
        "• Improved weather-based food recommendations",
        "• Security enhancements and performance optimizations",
        "• Bug fixes and user experience improvements"
    ]

    return "\n".join(ko_lines[:4]), "\n".join(en_lines[:4])

def main():
    build_number = sys.argv[1] if len(sys.argv) > 1 else "default"
    print(f"Generating release notes for build {build_number}...")

    commits = get_recent_commits(15)
    md_content = get_release_notes_md()
    
    gemini_key = os.environ.get("GEMINI_API_KEY", "").strip()
    ko_notes = None
    en_notes = None

    if gemini_key:
        print("GEMINI_API_KEY detected. Requesting AI-generated release notes...")
        ko_notes, en_notes = generate_notes_with_gemini(gemini_key, commits, md_content)

    if not ko_notes or not en_notes:
        print("Using smart fallback for release notes...")
        ko_notes, en_notes = generate_fallback_notes(commits, md_content)

    # Truncate to 480 chars (Play Store hard limit: 500)
    ko_notes = ko_notes[:480]
    en_notes = en_notes[:480]

    print("\n--- Generated Korean Release Notes ---")
    print(ko_notes)
    print("\n--- Generated English Release Notes ---")
    print(en_notes)

    # Write files for Fastlane (Google Play Console primary registered locale: ko-KR)
    targets = [
        ("ko-KR", ko_notes),
    ]

    for locale, content in targets:
        dir_path = os.path.join("android", "fastlane", "metadata", "android", locale, "changelogs")
        os.makedirs(dir_path, exist_ok=True)
        
        files_to_write = ["default.txt"]
        if build_number != "default":
            files_to_write.append(f"{build_number}.txt")

        for fname in files_to_write:
            fpath = os.path.join(dir_path, fname)
            with open(fpath, "w", encoding="utf-8") as f:
                f.write(content.strip() + "\n")
            print(f"Wrote release notes to {fpath}")

if __name__ == "__main__":
    main()
