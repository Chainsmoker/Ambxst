#!/usr/bin/env python3
import sys
import os
import json
import time
import urllib.request
import urllib.error
import hashlib
import colorsys

# Setup Cache Directory
CACHE_DIR = os.path.expanduser(os.environ.get("XDG_CACHE_HOME", "~/.cache"))
AMBXST_CACHE_DIR = os.path.join(CACHE_DIR, "ambxst")
os.makedirs(AMBXST_CACHE_DIR, exist_ok=True)

# Cache Expiry configuration (in seconds)
CACHE_EXPIRY = {
    "news": 900,    # 15 minutes
    "cve": 1800,    # 30 minutes
    "redis": 3600   # 1 hour
}

# User-Agent to prevent getting blocked by APIs
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_tag_color(tag):
    """Generate a deterministic, beautiful pastel color based on the tag string."""
    h = sum(ord(c) for c in tag) % 360
    # Use standard HSL to RGB conversion for a vibrant but soft pastel color
    r, g, b = colorsys.hls_to_rgb(h / 360.0, 0.65, 0.75)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

def fetch_json(url):
    """Fetch JSON from a URL with custom headers and timeout."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=8) as response:
        return json.loads(response.read().decode('utf-8'))

def parse_relative_time(published_at):
    """Convert ISO timestamp or string into a friendly relative time (e.g. '2h ago')."""
    try:
        # Standard isoformat parsing (compatible with older Python versions)
        # published_at e.g. "2026-05-24T12:00:00Z"
        clean_time = published_at.replace("Z", "+00:00")
        import datetime
        pub_dt = datetime.datetime.fromisoformat(clean_time)
        now_dt = datetime.datetime.now(datetime.timezone.utc)
        diff = now_dt - pub_dt
        
        seconds = diff.total_seconds()
        if seconds < 60:
            return "just now"
        minutes = seconds / 60
        if minutes < 60:
            return f"{int(minutes)}m ago"
        hours = minutes / 60
        if hours < 24:
            return f"{int(hours)}h ago"
        days = hours / 24
        return f"{int(days)}d ago"
    except Exception:
        return "recently"

def get_tech_news():
    """Fetch latest tech/programming articles from Dev.to API."""
    url = "https://dev.to/api/articles?tag=programming&per_page=12"
    raw_data = fetch_json(url)
    
    formatted = []
    for item in raw_data:
        # Resolve tag and color
        tags = item.get("tag_list", [])
        tag = tags[0].capitalize() if tags else "Tech"
        
        # Calculate human-readable source/time
        pub_date = item.get("published_at", "")
        rel_time = parse_relative_time(pub_date)
        author = item.get("user", {}).get("name", "Dev.to")
        source_str = f"{author} · {rel_time}"
        
        formatted.append({
            "title": item.get("title", ""),
            "source": source_str,
            "tag": tag,
            "tagColor": get_tag_color(tag),
            "image": item.get("cover_image") or item.get("social_image") or "",
            "excerpt": item.get("description", "")
        })
    return formatted

def get_cves():
    """Fetch latest CVEs from CIRCL vulnerability database."""
    url = "https://cve.circl.lu/api/last"
    raw_data = fetch_json(url)
    
    formatted = []
    for item in raw_data:
        # Map CVSS score
        score_val = item.get("cvss")
        if score_val is None:
            score_val = 5.0
        else:
            try:
                score_val = float(score_val)
            except ValueError:
                score_val = 5.0
                
        # Severity ranking & color
        if score_val >= 9.0:
            severity = "CRITICAL"
            color = "#E07556"
        elif score_val >= 7.0:
            severity = "HIGH"
            color = "#ff8a4a"
        elif score_val >= 4.0:
            severity = "MEDIUM"
            color = "#ffe57a"
        elif score_val > 0.0:
            severity = "LOW"
            color = "#7f8fa6"
        else:
            severity = "UNKNOWN"
            color = "#7f8fa6"
            
        formatted.append({
            "cve": item.get("id", "CVE-Unknown"),
            "severity": severity,
            "score": f"{score_val:.1f}",
            "color": color,
            "description": item.get("summary", "No description provided.")
        })
    return formatted

def get_redis_news():
    """Fetch Redis articles from Dev.to API."""
    url = "https://dev.to/api/articles?tag=redis&per_page=12"
    raw_data = fetch_json(url)
    
    formatted = []
    for item in raw_data:
        # Resolve tag and color
        tags = item.get("tag_list", [])
        tag = tags[0].upper() if tags else "REDIS"
        
        # Calculate human-readable source/time
        pub_date = item.get("published_at", "")
        rel_time = parse_relative_time(pub_date)
        author = item.get("user", {}).get("name", "Redis Dev")
        source_str = f"{author} · {rel_time}"
        
        formatted.append({
            "title": item.get("title", ""),
            "source": source_str,
            "tag": tag,
            "tagColor": "#e05638" if tag == "REDIS" else get_tag_color(tag),
            "image": item.get("cover_image") or item.get("social_image") or "",
            "excerpt": item.get("description", "")
        })
    return formatted

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Missing mode argument. Choose 'news', 'cve', or 'redis'."}))
        sys.exit(1)
        
    mode = sys.argv[1].lower()
    if mode not in CACHE_EXPIRY:
        print(json.dumps({"error": f"Invalid mode '{mode}'. Choose 'news', 'cve', or 'redis'."}))
        sys.exit(1)
        
    cache_file = os.path.join(AMBXST_CACHE_DIR, f"news_cache_{mode}.json")
    
    # Check cache validity
    cache_valid = False
    if os.path.exists(cache_file):
        mtime = os.path.getmtime(cache_file)
        if time.time() - mtime < CACHE_EXPIRY[mode]:
            cache_valid = True
            
    if cache_valid:
        try:
            with open(cache_file, "r") as f:
                print(f.read())
                sys.exit(0)
        except Exception:
            pass  # Fallback to fetching if cache reading fails
            
    # Cache is invalid or missing, fetch fresh data
    try:
        if mode == "news":
            data = get_tech_news()
        elif mode == "cve":
            data = get_cves()
        elif mode == "redis":
            data = get_redis_news()
        else:
            data = []
            
        # Save to cache
        try:
            with open(cache_file, "w") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to save cache: {e}", file=sys.stderr)
            
        print(json.dumps(data))
        
    except Exception as e:
        # In case of network errors or api block, fallback to old cache if available
        if os.path.exists(cache_file):
            try:
                with open(cache_file, "r") as f:
                    print(f.read())
                    print(f"Warning: Fetch failed, using cache. Error: {e}", file=sys.stderr)
                    sys.exit(0)
            except Exception:
                pass
                
        # If no cache exists, return an error message nicely in JSON
        print(json.dumps({"error": f"Failed to fetch data: {str(e)}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
