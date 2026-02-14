import requests
import json

# Use local server
API_URL = "http://localhost:5000/api/playlist"

payload = {
    "url": "https://open.spotify.com/playlist/5CpXDyvoA25wURjqF61qgv?si=5e08e0a3e49a4ea2"
}

print("🔍 Testing LOCAL /api/playlist endpoint...")
response = requests.post(API_URL, json=payload, timeout=120)

print(f"📡 Status: {response.status_code}\n")

data = response.json()

playlist = data.get('playlist', {})
print(f"📋 Playlist: {playlist.get('name')}")
print(f"👤 Owner: {playlist.get('ownerName')}")
print(f"🖼️ Cover: {playlist.get('coverImageUrl')}\n")

if 'results' in data:
    print("🎵 Tracks:")
    for i, track in enumerate(data['results'], 1):
        print(f"\n{i}. {track['title']}")
        print(f"   Artists: {', '.join(track['artists'])}")
        print(f"   YouTube: {track.get('youtubeId')}")
        print(f"   Album Art: {track.get('albumArt')}")
        
        # Check if album art is different from playlist cover
        if track.get('albumArt') == playlist.get('coverImageUrl'):
            print(f"   ⚠️  SAME AS PLAYLIST COVER")
        else:
            print(f"   ✅ UNIQUE ALBUM ART")