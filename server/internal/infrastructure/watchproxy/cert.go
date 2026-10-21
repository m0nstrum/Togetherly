package watchproxy

import (
	"crypto/tls"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// CertFiles — сертификат прокси с диска. Либо явные файлы, либо хранилище
// Caddy (том caddy-data): Caddy сам получает и продлевает сертификат домена,
// прокси берёт тот же. Файлы перечитываются, когда меняются.
type CertFiles struct {
	CertFile, KeyFile string
	CaddyDir, Domain  string

	mu      sync.Mutex
	cert    *tls.Certificate
	mtime   time.Time
	checked time.Time
}

func (c *CertFiles) paths() (string, string, error) {
	if c.CertFile != "" && c.KeyFile != "" {
		return c.CertFile, c.KeyFile, nil
	}
	if c.CaddyDir == "" || c.Domain == "" {
		return "", "", errors.New("watchproxy: нет ни файлов сертификата, ни хранилища Caddy")
	}
	// certificates/<издатель>/<домен>/<домен>.crt — издатель бывает разный
	// (Let's Encrypt, ZeroSSL).
	found, _ := filepath.Glob(filepath.Join(c.CaddyDir, "certificates", "*", c.Domain, c.Domain+".crt"))
	if len(found) == 0 {
		return "", "", errors.New("watchproxy: Caddy ещё не получил сертификат " + c.Domain)
	}
	cert := found[0]
	return cert, cert[:len(cert)-len(".crt")] + ".key", nil
}

// GetCertificate — для tls.Config.
func (c *CertFiles) GetCertificate(*tls.ClientHelloInfo) (*tls.Certificate, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cert != nil && time.Since(c.checked) < time.Minute {
		return c.cert, nil
	}
	c.checked = time.Now()
	certPath, keyPath, err := c.paths()
	if err != nil {
		if c.cert != nil {
			return c.cert, nil
		}
		return nil, err
	}
	st, err := os.Stat(certPath)
	if err != nil {
		if c.cert != nil {
			return c.cert, nil
		}
		return nil, err
	}
	if c.cert != nil && st.ModTime().Equal(c.mtime) {
		return c.cert, nil
	}
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		if c.cert != nil {
			return c.cert, nil
		}
		return nil, err
	}
	c.cert, c.mtime = &cert, st.ModTime()
	return c.cert, nil
}
