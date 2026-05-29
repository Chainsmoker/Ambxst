#!/usr/bin/env python3
import sys
import os
import json
import time
import urllib.request
import urllib.error
import colorsys
import hashlib

# Setup Cache Directory
CACHE_DIR = os.path.expanduser(os.environ.get("XDG_CACHE_HOME", "~/.cache"))
AMBXST_CACHE_DIR = os.path.join(CACHE_DIR, "ambxst")
os.makedirs(AMBXST_CACHE_DIR, exist_ok=True)
IMAGES_DIR = os.path.join(AMBXST_CACHE_DIR, "images")
os.makedirs(IMAGES_DIR, exist_ok=True)

def download_image(url):
    """Download image to local cache and return local file:// path to prevent Qt SSL issues."""
    if not url or not url.startswith("http"):
        return ""
    try:
        url_hash = hashlib.md5(url.encode('utf-8')).hexdigest()
        
        # Determine extension
        ext = ".jpg"
        if ".png" in url.lower():
            ext = ".png"
        elif ".webp" in url.lower():
            ext = ".webp"
        elif ".gif" in url.lower():
            ext = ".gif"
            
        local_filename = f"{url_hash}{ext}"
        local_path = os.path.join(IMAGES_DIR, local_filename)
        
        if not os.path.exists(local_path):
            req = urllib.request.Request(
                url,
                headers={"User-Agent": USER_AGENT}
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                with open(local_path, "wb") as f:
                    f.write(response.read())
                    
        return f"file://{local_path}"
    except Exception as e:
        print(f"Warning: Failed to download image {url}: {e}", file=sys.stderr)
        return url

def download_header_image():
    """Ensure the header background image is cached locally."""
    url = "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600&auto=format&fit=crop&q=80"
    local_path = os.path.join(IMAGES_DIR, "header_bg.jpg")
    if not os.path.exists(local_path):
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": USER_AGENT}
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                with open(local_path, "wb") as f:
                    f.write(response.read())
        except Exception as e:
            print(f"Warning: Failed to download header bg: {e}", file=sys.stderr)

# Cache Expiry configuration (in seconds)
CACHE_EXPIRY = {
    "news": 900,      # 15 minutes
    "cve": 1800,      # 30 minutes
    "reddit": 1800    # 30 minutes
}

# User-Agent to prevent getting blocked by APIs (highly important for Reddit)
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_tag_color(tag):
    """Generate a deterministic, beautiful pastel color based on the tag string."""
    h = sum(ord(c) for c in tag) % 360
    r, g, b = colorsys.hls_to_rgb(h / 360.0, 0.65, 0.75)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

def fetch_json(url):
    """Fetch JSON from a URL with custom headers and timeout."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode('utf-8'))

def parse_relative_time(published_at):
    """Convert ISO timestamp or string into a friendly relative time (e.g. '2h ago')."""
    try:
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
    """Fetch latest technology headlines from NewsAPI.org."""
    api_key = "c3781d47f5fd4b7daaa86e0c023d47e4"
    url = f"https://newsapi.org/v2/top-headlines?category=technology&language=en&pageSize=30&apiKey={api_key}"
    raw_data = fetch_json(url)
    
    articles = raw_data.get("articles", [])
    formatted = []
    
    for item in articles:
        title = item.get("title", "")
        source_elem = item.get("source", {}) or {}
        source_name = source_elem.get("name", "Tech News")
        
        # Clean source suffix from title if present
        if title and " - " in title:
            parts = title.rsplit(" - ", 1)
            if len(parts) == 2 and parts[1].strip().lower() == source_name.strip().lower():
                title = parts[0].strip()
                
        pub_date = item.get("publishedAt", "")
        rel_time = parse_relative_time(pub_date)
        source_str = f"{source_name} · {rel_time}"
        
        img_url = item.get("urlToImage") or ""
        local_img = download_image(img_url) if img_url else ""
        
        excerpt = item.get("description") or item.get("content") or "Read the full coverage online."
        if len(excerpt) > 200:
            excerpt = excerpt[:200] + "..."
            
        # Short tag based on source name
        clean_tag = source_name.strip()
        if clean_tag.lower().startswith("the "):
            clean_tag = clean_tag[4:]
        first_word = clean_tag.split()[0] if clean_tag.split() else "Tech"
        tag = first_word[:12]
        
        formatted.append({
            "title": title,
            "source": source_str,
            "tag": tag,
            "tagColor": get_tag_color(tag),
            "image": local_img,
            "excerpt": excerpt,
            "url": item.get("url", "")
        })
    return formatted

OPENCVE_API = "https://app.opencve.io/api"

def _opencve_token():
    """Token de OpenCVE. Se lee de $OPENCVE_TOKEN o del archivo
    $XDG_CONFIG_HOME/ambxst/opencve.token. NO se commitea (es un secreto)."""
    tok = os.environ.get("OPENCVE_TOKEN", "").strip()
    if tok:
        return tok
    cfg = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    try:
        with open(os.path.join(cfg, "ambxst", "opencve.token")) as f:
            return f.read().strip()
    except OSError:
        return ""

def fetch_json_auth(url, token):
    """Fetch JSON con Authorization: Bearer (para la API de OpenCVE)."""
    req = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
        "Authorization": f"Bearer {token}",
    })
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))

def _cve_severity(score_val):
    """Mapea un CVSS score (o None) a (severity, color, score_str)."""
    if score_val is None:
        return "UNKNOWN", "#7f8fa6", "—"
    if score_val >= 9.0:
        return "CRITICAL", "#E07556", f"{score_val:.1f}"
    if score_val >= 7.0:
        return "HIGH", "#ff8a4a", f"{score_val:.1f}"
    if score_val >= 4.0:
        return "MEDIUM", "#ffe57a", f"{score_val:.1f}"
    if score_val > 0.0:
        return "LOW", "#7f8fa6", f"{score_val:.1f}"
    return "UNKNOWN", "#7f8fa6", "—"

def _opencve_score(detail):
    """Mejor CVSS disponible del detalle de OpenCVE; fallback a threat_severity."""
    metrics = detail.get("metrics", {}) or {}
    for key in ("cvssV4_0", "cvssV3_1", "cvssV3_0", "cvssV2_0"):
        data = (metrics.get(key) or {}).get("data") or {}
        s = data.get("score")
        if s is not None:
            try:
                return float(s)
            except (ValueError, TypeError):
                pass
    ts = (metrics.get("threat_severity") or {}).get("data")
    if isinstance(ts, str):
        t = ts.lower()
        if "critical" in t:
            return 9.5
        if "important" in t or "high" in t:
            return 8.0
        if "moderate" in t or "medium" in t:
            return 5.5
        if "low" in t:
            return 2.5
    return None

def get_cves():
    """Fetch latest CVEs from OpenCVE (app.opencve.io).

    La lista (página 1 = más recientes por updated_at) sólo trae id/descripción,
    así que pedimos el detalle de cada CVE EN PARALELO para sacar el CVSS real.
    """
    from concurrent.futures import ThreadPoolExecutor

    token = _opencve_token()
    if not token:
        raise RuntimeError(
            "OpenCVE token not configured "
            "(set $OPENCVE_TOKEN or ~/.config/ambxst/opencve.token)")

    listing = fetch_json_auth(f"{OPENCVE_API}/cve", token)
    results = listing.get("results", []) if isinstance(listing, dict) else []

    def enrich(item):
        cve_id = item.get("cve_id", "CVE-Unknown")
        description = item.get("description") or "No description provided."
        if len(description) > 200:
            description = description[:200] + "..."

        score_val = None
        try:
            detail = fetch_json_auth(f"{OPENCVE_API}/cve/{cve_id}", token)
            score_val = _opencve_score(detail)
        except Exception:
            pass

        severity, color, score_str = _cve_severity(score_val)
        cve_url = (f"https://nvd.nist.gov/vuln/detail/{cve_id}"
                   if cve_id.upper().startswith("CVE-") else "")
        return {
            "cve": cve_id,
            "severity": severity,
            "score": score_str,
            "color": color,
            "description": description,
            "url": cve_url,
        }

    with ThreadPoolExecutor(max_workers=8) as ex:
        return list(ex.map(enrich, results))

def get_reddit_posts():
    """Fetch latest tech posts from r/technology on Reddit."""
    url = "https://www.reddit.com/r/technology/new.json?limit=30"
    raw_data = fetch_json(url)
    
    formatted = []
    posts = raw_data.get("data", {}).get("children", [])
    for post in posts:
        data = post.get("data", {})
        
        if data.get("stickied"):
            continue
            
        title = data.get("title", "")
        author = data.get("author", "Reddit")
        subreddit = data.get("subreddit_name_prefixed", "r/technology")
        
        created_utc = data.get("created_utc", time.time())
        import datetime
        pub_dt = datetime.datetime.fromtimestamp(created_utc, datetime.timezone.utc)
        now_dt = datetime.datetime.now(datetime.timezone.utc)
        diff = now_dt - pub_dt
        seconds = diff.total_seconds()
        
        if seconds < 60:
            rel_time = "just now"
        elif seconds < 3600:
            rel_time = f"{int(seconds / 60)}m ago"
        elif seconds < 86400:
            rel_time = f"{int(seconds / 3600)}h ago"
        else:
            rel_time = f"{int(seconds / 86400)}d ago"
            
        source_str = f"{subreddit} · u/{author} · {rel_time}"
        
        # Extract premium preview image
        image_url = ""
        preview = data.get("preview")
        if preview and "images" in preview:
            images = preview["images"]
            if images:
                source_img = images[0].get("source", {})
                image_url = source_img.get("url", "")
                image_url = image_url.replace("&amp;", "&")
                
        if not image_url:
            thumbnail = data.get("thumbnail", "")
            if thumbnail.startswith("http"):
                image_url = thumbnail
                
        local_img = download_image(image_url) if image_url else ""
        
        excerpt = data.get("selftext", "")
        if not excerpt:
            domain = data.get("domain", "")
            excerpt = f"Link: {domain} — Shared on r/technology."
        elif len(excerpt) > 180:
            excerpt = excerpt[:180] + "..."
            
        tag = "Reddit"
        
        formatted.append({
            "title": title,
            "source": source_str,
            "tag": tag,
            "tagColor": "#ff4500",  # Reddit Orange
            "image": local_img,
            "excerpt": excerpt,
            "url": data.get("url") if data.get("url") and data.get("url").startswith("http") else f"https://reddit.com{data.get('permalink')}"
        })
    return formatted

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Missing mode argument. Choose 'news', 'cve', or 'reddit'."}))
        sys.exit(1)
        
    mode = sys.argv[1].lower()
    if mode not in CACHE_EXPIRY:
        print(json.dumps({"error": f"Invalid mode '{mode}'. Choose 'news', 'cve', or 'reddit'."}))
        sys.exit(1)
        
    # Always ensure header image is downloaded
    download_header_image()
    
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
            pass
            
    # Cache is invalid or missing, fetch fresh data
    try:
        if mode == "news":
            data = get_tech_news()
        elif mode == "cve":
            data = get_cves()
        elif mode == "reddit":
            data = get_reddit_posts()
        else:
            data = []
            
        try:
            with open(cache_file, "w") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to save cache: {e}", file=sys.stderr)
            
        print(json.dumps(data))
        
    except Exception as e:
        if os.path.exists(cache_file):
            try:
                with open(cache_file, "r") as f:
                    print(f.read())
                    print(f"Warning: Fetch failed, using cache. Error: {e}", file=sys.stderr)
                    sys.exit(0)
            except Exception:
                pass
                
        print(json.dumps({"error": f"Failed to fetch data: {str(e)}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
