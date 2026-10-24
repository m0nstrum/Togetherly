package meta

import (
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

const MapOrigin = "https://tiles.openfreemap.org"

var mapVersion = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// MapTileURL accepts coordinates, never a user-selected host or arbitrary path.
func MapTileURL(version, z, x, y string) (string, bool) {
	if !mapVersion.MatchString(version) {
		return "", false
	}
	coords := []string{z, x, y}
	values := make([]int, 3)
	for i, raw := range coords {
		n, err := strconv.Atoi(raw)
		if err != nil || strconv.Itoa(n) != raw || n < 0 {
			return "", false
		}
		values[i] = n
	}
	if values[0] > 14 || values[1] >= 1<<values[0] || values[2] >= 1<<values[0] {
		return "", false
	}
	return fmt.Sprintf("%s/planet/%s/%s/%s/%s.pbf", MapOrigin, version, z, x, y), true
}

func MapTemplateVersion(raw string) (string, bool) {
	prefix := MapOrigin + "/planet/"
	suffix := "/{z}/{x}/{y}.pbf"
	if !strings.HasPrefix(raw, prefix) || !strings.HasSuffix(raw, suffix) {
		return "", false
	}
	version := strings.TrimSuffix(strings.TrimPrefix(raw, prefix), suffix)
	return version, mapVersion.MatchString(version)
}

func mapKind(u *url.URL) (Kind, bool) {
	if u.Host != "tiles.openfreemap.org" || u.RawQuery != "" || u.Fragment != "" {
		return 0, false
	}
	if u.Path == "/planet" {
		return KindJSON, true
	}
	parts := strings.Split(strings.TrimPrefix(u.Path, "/planet/"), "/")
	if len(parts) != 4 || !strings.HasSuffix(parts[3], ".pbf") {
		return 0, false
	}
	canonical, ok := MapTileURL(parts[0], parts[1], parts[2], strings.TrimSuffix(parts[3], ".pbf"))
	return KindTile, ok && canonical == u.String()
}
