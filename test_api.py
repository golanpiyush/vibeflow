import requests
import json

# Your Vercel API URL
API_URL = "https://spotify-youtube-api.vercel.app/api/convert"

# Test with a single track
def test_single_track():
    payload = {
        "tracks": [
            {"title": "Honeythief", "artists": ["Halou"]}
        ]
    }
    
    print("🔍 Testing API with single track...")
    print(f"📤 Sending: {json.dumps(payload, indent=2)}\n")
    
    try:
        response = requests.post(
            API_URL,
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=30
        )
        
        print(f"📡 Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ API Response:")
            print(json.dumps(data, indent=2))
            
            # Show results
            if "results" in data:
                for result in data["results"]:
                    if result.get("success"):
                        print(f"\n✅ Found: {result['title']}")
                        print(f"   YouTube ID: {result['youtubeId']}")
                        print(f"   Watch: https://www.youtube.com/watch?v={result['youtubeId']}")
                    else:
                        print(f"\n❌ Failed: {result['title']}")
                        print(f"   Error: {result.get('error', 'Unknown')}")
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.Timeout:
        print("❌ Error: Request timed out (took longer than 30 seconds)")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error: {e}")
    except json.JSONDecodeError:
        print(f"❌ Error: Invalid JSON response")
        print(f"Response: {response.text}")


# Test with multiple tracks
def test_multiple_tracks():
    payload = {
        "tracks": [
            {"title": "Honeythief", "artists": ["Halou"]},
            {"title": "Girls on Film", "artists": ["Duran Duran"]},
            {"title": "28 Days Later Main Theme", "artists": ["Geek Music"]}
        ]
    }
    
    print("\n" + "="*60)
    print("🔍 Testing API with multiple tracks...")
    print(f"📤 Sending {len(payload['tracks'])} tracks\n")
    
    try:
        response = requests.post(
            API_URL,
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=60
        )
        
        print(f"📡 Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            
            # Show summary
            if "summary" in data:
                summary = data["summary"]
                print(f"\n📊 Summary:")
                print(f"   Total: {summary['total']}")
                print(f"   ✅ Successful: {summary['successful']}")
                print(f"   ❌ Failed: {summary['failed']}")
            
            # Show results
            print(f"\n📋 Results:")
            if "results" in data:
                for i, result in enumerate(data["results"], 1):
                    print(f"\n{i}. {result['title']} - {', '.join(result['artists'])}")
                    if result.get("success"):
                        print(f"   ✅ YouTube ID: {result['youtubeId']}")
                        print(f"   🎬 {result.get('youtubeTitle', 'N/A')}")
                    else:
                        print(f"   ❌ {result.get('error', 'Failed')}")
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"Response: {response.text}")
            
    except requests.exceptions.Timeout:
        print("❌ Error: Request timed out (took longer than 60 seconds)")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error: {e}")
    except json.JSONDecodeError:
        print(f"❌ Error: Invalid JSON response")
        print(f"Response: {response.text}")


if __name__ == "__main__":
    print("🚀 Testing Spotify-YouTube API")
    print("="*60)
    
    # Test single track
    test_single_track()
    
    # Test multiple tracks
    test_multiple_tracks()
    
    print("\n" + "="*60)
    print("✅ Testing complete!")