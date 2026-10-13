package ioscore

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/thejerf/suture/v4"

	"github.com/syncthing/syncthing/internal/db"
	"github.com/syncthing/syncthing/internal/slogutil"
	"github.com/syncthing/syncthing/lib/build"
	"github.com/syncthing/syncthing/lib/config"
	"github.com/syncthing/syncthing/lib/events"
	"github.com/syncthing/syncthing/lib/locations"
	"github.com/syncthing/syncthing/lib/protocol"
	"github.com/syncthing/syncthing/lib/svcutil"
	"github.com/syncthing/syncthing/lib/syncthing"
)

const (
	defaultGUIAddress = "http://127.0.0.1:8384"
	defaultAPIKey     = "ios-local-syncthing-core"
	guiStateFile      = "ios-gui.txt"
	apiKeyStateFile   = "ios-apikey.txt"
)

// resolveGUIAddress returns a persisted random loopback address with a random
// port, or the caller-provided address if it is non-default.  The first time
// the app runs, a random high port (49152-65535) is generated and persisted so
// that subsequent launches reuse the same port.
func resolveGUIAddress(homeDir, requested string) string {
	if requested != "" && requested != defaultGUIAddress {
		return requested
	}
	statePath := filepath.Join(homeDir, guiStateFile)
	if data, err := os.ReadFile(statePath); err == nil {
		if s := strings.TrimSpace(string(data)); s != "" {
			return s
		}
	}
	port, err := rand.Int(rand.Reader, big.NewInt(16384))
	if err != nil {
		port = big.NewInt(8000) // fallback
	}
	addr := "http://127.0.0.1:" + strconv.Itoa(49152+int(port.Int64()))
	_ = os.WriteFile(statePath, []byte(addr), 0o600)
	return addr
}

// resolveAPIKey returns a persisted random API key, or the caller-provided key
// if it is non-default.  The first time the app runs, 32 random bytes are hex
// encoded and persisted so that subsequent launches reuse the same key.
func resolveAPIKey(homeDir, requested string) string {
	if requested != "" && requested != defaultAPIKey {
		return requested
	}
	statePath := filepath.Join(homeDir, apiKeyStateFile)
	if data, err := os.ReadFile(statePath); err == nil {
		if s := strings.TrimSpace(string(data)); s != "" {
			return s
		}
	}
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return defaultAPIKey // fallback (should not happen)
	}
	key := hex.EncodeToString(buf)
	_ = os.WriteFile(statePath, []byte(key), 0o600)
	return key
}

var runtimeState = &runner{}

type runner struct {
	mut       sync.Mutex
	app       *syncthing.App
	early     *suture.Supervisor
	cancel    context.CancelFunc
	database  db.DB
	starting  bool
	startID   uint64
	home      string
	gui       string
	apiKey    string
	device    string
	syncRoot  string
	startedAt time.Time
	lastError string
	step      string
}

// Start launches Syncthing core in the current process.
func Start(homeDir string) error {
	return StartWithConfig(homeDir, defaultGUIAddress, defaultAPIKey)
}

// StartWithConfig launches Syncthing core with an app-controlled home, GUI address, and API key.
func StartWithConfig(homeDir, guiAddress, apiKey string) error {
	return StartWithConfigAndDeviceName(homeDir, guiAddress, apiKey, "")
}

// StartWithConfigAndDeviceName launches Syncthing core and applies an iOS-provided local device name.
func StartWithConfigAndDeviceName(homeDir, guiAddress, apiKey, deviceName string) error {
	return StartWithConfigDeviceNameAndSyncRoot(homeDir, guiAddress, apiKey, deviceName, "")
}

// StartWithConfigDeviceNameAndSyncRoot launches Syncthing core with a separate user-visible sync root.
func StartWithConfigDeviceNameAndSyncRoot(homeDir, guiAddress, apiKey, deviceName, syncRoot string) error {
	if homeDir == "" {
		return errors.New("home directory is required")
	}
	// Resolve persisted random port and API key when defaults are requested,
	// so other apps on the device cannot guess the REST API endpoint.
	guiAddress = resolveGUIAddress(homeDir, guiAddress)
	apiKey = resolveAPIKey(homeDir, apiKey)

	runtimeState.mut.Lock()
	if runtimeState.app != nil || runtimeState.starting {
		runtimeState.mut.Unlock()
		return nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	runtimeState.startID++
	startID := runtimeState.startID
	runtimeState.starting = true
	runtimeState.cancel = cancel
	runtimeState.home = homeDir
	runtimeState.gui = guiAddress
	runtimeState.apiKey = apiKey
	runtimeState.device = deviceName
	runtimeState.syncRoot = syncRoot
	runtimeState.lastError = ""
	runtimeState.step = "queued"
	runtimeState.mut.Unlock()

	go startCore(ctx, cancel, startID, homeDir, guiAddress, apiKey, deviceName, syncRoot)
	return nil
}

func startCore(ctx context.Context, cancel context.CancelFunc, startID uint64, homeDir, guiAddress, apiKey, deviceName, syncRoot string) {
	app, early, sdb, err := buildCore(ctx, cancel, homeDir, guiAddress, apiKey, deviceName, syncRoot)

	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	if runtimeState.startID != startID || runtimeState.cancel == nil {
		stopCore(app, sdb, cancel)
		return
	}
	runtimeState.starting = false
	if err != nil {
		runtimeState.cancel = nil
		runtimeState.lastError = err.Error()
		runtimeState.step = "failed"
		return
	}
	runtimeState.app = app
	runtimeState.early = early
	runtimeState.cancel = cancel
	runtimeState.database = sdb
	runtimeState.home = homeDir
	runtimeState.gui = guiAddress
	runtimeState.apiKey = apiKey
	runtimeState.device = deviceName
	runtimeState.syncRoot = syncRoot
	runtimeState.startedAt = time.Now()
	runtimeState.lastError = ""
	runtimeState.step = "running"
}

func buildCore(ctx context.Context, cancel context.CancelFunc, homeDir, guiAddress, apiKey, deviceName, syncRoot string) (*syncthing.App, *suture.Supervisor, db.DB, error) {
	setStep("configure locations")
	if err := configureLocations(homeDir, syncRoot); err != nil {
		return nil, nil, nil, err
	}
	setStep("ensure home")
	if err := syncthing.EnsureDir(homeDir, 0o700); err != nil {
		return nil, nil, nil, err
	}

	setStep("configure environment")
	os.Setenv("STGUIADDRESS", guiAddress)
	os.Setenv("STGUIAPIKEY", apiKey)
	os.Setenv("STNOUPGRADE", "1")
	os.Setenv("STNORESTART", "1")
	os.Setenv("STVERSIONEXTRA", "Syncthing iOS")
	build.AddTag("ios")

	// Aggressive GC tuning for iOS: the default GOGC=100 lets the heap double
	// before collecting, and Go never returns memory to the OS on its own.
	// iOS jetsam kills apps by physical RSS, so we lower the trigger and cap
	// the soft memory limit so collections happen earlier and memory is
	// returned to the OS more aggressively.
	debug.SetGCPercent(25)
	debug.SetMemoryLimit(400 << 20) // 400 MB soft limit

	slogutil.SetDefaultLevel(slog.LevelInfo)
	slogutil.SetLevelOverrides("")

	setStep("certificate")
	cert, err := syncthing.LoadOrGenerateCertificate(
		locations.Get(locations.CertFile),
		locations.Get(locations.KeyFile),
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("certificate: %w", err)
	}

	early := suture.New("ios-early", svcutil.SpecWithDebugLogger())
	evLogger := events.NewLogger()
	setStep("early services")
	early.ServeBackground(ctx)
	early.Add(evLogger)

	setStep("load config")
	cfgWrapper, err := loadMobileConfig(locations.Get(locations.ConfigFile), homeDir, syncRoot, cert, evLogger, guiAddress, apiKey, deviceName)
	if err != nil {
		cancel()
		return nil, nil, nil, fmt.Errorf("config: %w", err)
	}
	setStep("config service")
	early.Add(cfgWrapper)
	config.RegisterInfoMetrics(cfgWrapper)

	setStep("database migration")
	if err := syncthing.TryMigrateDatabase(ctx, 10920*time.Hour); err != nil {
		cancel()
		return nil, nil, nil, fmt.Errorf("database migration: %w", err)
	}

	setStep("open database")
	sdb, err := syncthing.OpenDatabase(locations.Get(locations.Database), 10920*time.Hour)
	if err != nil {
		cancel()
		return nil, nil, nil, fmt.Errorf("database: %w", err)
	}

	setStep("create app")
	app, err := syncthing.New(cfgWrapper, sdb, evLogger, cert, syncthing.Options{
		NoUpgrade:             true,
		DBMaintenanceInterval: 8 * time.Hour,
	})
	if err != nil {
		cancel()
		sdb.Close()
		return nil, nil, nil, fmt.Errorf("app: %w", err)
	}
	setStep("start app")
	if err := app.Start(); err != nil {
		cancel()
		sdb.Close()
		return nil, nil, nil, fmt.Errorf("start: %w", err)
	}

	setStep("app started")
	return app, early, sdb, nil
}

func setStep(step string) {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	runtimeState.step = step
}

func loadMobileConfig(path, homeDir, syncRoot string, cert tls.Certificate, evLogger events.Logger, guiAddress, apiKey, deviceName string) (config.Wrapper, error) {
	myID := protocol.NewDeviceID(cert.Certificate[0])

	cfgWrapper, originalVersion, err := config.Load(path, myID, evLogger)
	if os.IsNotExist(err) {
		cfg := config.New(myID)
		if err := prepareMobileConfig(&cfg, myID, homeDir, syncRoot, guiAddress, apiKey, deviceName); err != nil {
			return nil, err
		}
		cfgWrapper = config.Wrap(path, cfg, myID, evLogger)
		if err := cfgWrapper.Save(); err != nil {
			return nil, fmt.Errorf("save default config: %w", err)
		}
		return cfgWrapper, nil
	}
	if errors.Is(err, io.EOF) {
		return nil, errors.New("failed to load config: unexpected end of file")
	}
	if err != nil {
		return nil, err
	}

	cfg := cfgWrapper.RawCopy()
	if err := prepareMobileConfig(&cfg, myID, homeDir, syncRoot, guiAddress, apiKey, deviceName); err != nil {
		return nil, err
	}
	// Only re-wrap and save if the prepared config differs from the original,
	// so we don't trigger a needless config-change cycle on every launch.
	original := cfgWrapper.RawCopy()
	if configEqual(cfg, original) {
		return cfgWrapper, nil
	}
	cfgWrapper = config.Wrap(path, cfg, myID, evLogger)
	if err := cfgWrapper.Save(); err != nil {
		if originalVersion != config.CurrentVersion {
			return nil, fmt.Errorf("save migrated config: %w", err)
		}
		return nil, fmt.Errorf("save mobile config: %w", err)
	}
	return cfgWrapper, nil
}

func prepareMobileConfig(cfg *config.Configuration, myID protocol.DeviceID, homeDir, syncRoot, guiAddress, apiKey, deviceName string) error {
	cfg.GUI.Enabled = true
	cfg.GUI.RawAddress = guiAddress
	cfg.GUI.APIKey = apiKey
	cfg.Options.StartBrowser = false
	cfg.Options.AutoUpgradeIntervalH = 0
	// Disable usage reporting and crash reporting (no consent dialog on iOS).
	cfg.Options.URAccepted = -1
	cfg.Options.URURL = ""
	cfg.Options.CREnabled = false
	cfg.Options.CRURL = ""
	// Disable version checks — we manage updates via the App Store.
	cfg.Options.ReleasesURL = ""
	// iOS doesn't expose Unix permissions to users; ignore them to avoid
	// perpetual permission-mismatch sync errors.
	cfg.Defaults.Folder.IgnorePerms = true
	// Set a sane default rescan interval for mobile (1 hour).
	cfg.Defaults.Folder.RescanIntervalS = 3600

	deviceName = strings.TrimSpace(deviceName)
	if deviceName == "" {
		deviceName = "Syncthing iPhone"
	}
	for index := range cfg.Devices {
		if cfg.Devices[index].DeviceID != myID {
			continue
		}
		currentName := strings.TrimSpace(cfg.Devices[index].Name)
		if currentName == "" || currentName == "localhost" || strings.HasPrefix(currentName, "unknown-dev") {
			cfg.Devices[index].Name = deviceName
		}
		break
	}

	if strings.TrimSpace(syncRoot) == "" {
		syncRoot = filepath.Join(homeDir, "Sync")
	}
	syncRoot = filepath.Clean(syncRoot)
	if err := os.MkdirAll(syncRoot, 0o700); err != nil {
		return fmt.Errorf("sync root: %w", err)
	}
	cfg.Defaults.Folder.Path = syncRoot
	cfg.Defaults.Folder.FSWatcherEnabled = false
	for index := range cfg.Folders {
		oldPath := strings.TrimSpace(cfg.Folders[index].Path)
		newPath := mobileFolderPath(syncRoot, cfg.Folders[index].ID)
		if filepath.Clean(oldPath) != newPath {
			if err := migrateFolderPath(oldPath, newPath, homeDir, syncRoot, cfg.Folders[index].ID); err != nil {
				return fmt.Errorf("migrate folder %s: %w", cfg.Folders[index].ID, err)
			}
			cfg.Folders[index].Path = newPath
		}
		cfg.Folders[index].FSWatcherEnabled = false
		if err := os.MkdirAll(cfg.Folders[index].Path, 0o700); err != nil {
			return fmt.Errorf("folder %s: %w", cfg.Folders[index].ID, err)
		}
		if err := os.MkdirAll(filepath.Join(cfg.Folders[index].Path, cfg.Folders[index].MarkerName), 0o700); err != nil {
			return fmt.Errorf("folder marker %s: %w", cfg.Folders[index].ID, err)
		}
	}
	return nil
}

// configEqual reports whether two configurations are semantically equal.
func configEqual(a, b config.Configuration) bool {
	return reflect.DeepEqual(a, b)
}

func mobileFolderPath(syncRoot, folderID string) string {
	folderID = strings.TrimSpace(folderID)
	if folderID == "" {
		folderID = "default"
	}
	return filepath.Join(syncRoot, filepath.Base(filepath.Clean(folderID)))
}

func migrateFolderPath(oldPath, newPath, homeDir, syncRoot, folderID string) error {
	sourcePath := strings.TrimSpace(oldPath)
	if sourcePath == "" || strings.HasPrefix(sourcePath, "~/") || !filepath.IsAbs(sourcePath) {
		sourcePath = ""
	} else {
		sourcePath = filepath.Clean(sourcePath)
	}
	newPath = filepath.Clean(newPath)
	if sourcePath == newPath {
		return nil
	}

	sourcePath, err := firstExistingDirectory(
		sourcePath,
		mobileFolderPath(filepath.Join(homeDir, "Sync"), folderID),
		mobileFolderPath(filepath.Join(filepath.Dir(syncRoot), "Syncthing"), folderID),
	)
	if err != nil || sourcePath == "" || sourcePath == newPath {
		return err
	}

	if err := os.MkdirAll(newPath, 0o700); err != nil {
		return err
	}
	return copyDirectoryContents(sourcePath, newPath)
}

func firstExistingDirectory(paths ...string) (string, error) {
	for _, path := range paths {
		path = strings.TrimSpace(path)
		if path == "" {
			continue
		}
		info, err := os.Stat(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return "", err
		}
		if info.IsDir() {
			return filepath.Clean(path), nil
		}
	}
	return "", nil
}

func copyDirectoryContents(sourcePath, destinationPath string) error {
	return filepath.WalkDir(sourcePath, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relativePath, err := filepath.Rel(sourcePath, path)
		if err != nil || relativePath == "." {
			return err
		}
		destination := filepath.Join(destinationPath, relativePath)
		if entry.IsDir() {
			return os.MkdirAll(destination, 0o700)
		}
		if _, err := os.Stat(destination); err == nil {
			return nil
		} else if !os.IsNotExist(err) {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		return copyFile(path, destination, info.Mode().Perm())
	})
}

func copyFile(sourcePath, destinationPath string, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(destinationPath), 0o700); err != nil {
		return err
	}
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()

	destination, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	defer destination.Close()

	_, err = io.Copy(destination, source)
	return err
}

func stopCore(app *syncthing.App, database db.DB, cancel context.CancelFunc) {
	if app != nil {
		app.Stop(svcutil.ExitSuccess)
		app.Wait()
	}
	if database != nil {
		database.Close()
	}
	if cancel != nil {
		cancel()
	}
}

// Stop shuts down the in-process Syncthing core.
func Stop() {
	runtimeState.mut.Lock()
	app := runtimeState.app
	database := runtimeState.database
	cancel := runtimeState.cancel
	runtimeState.app = nil
	runtimeState.database = nil
	runtimeState.cancel = nil
	runtimeState.early = nil
	runtimeState.starting = false
	runtimeState.startedAt = time.Time{}
	runtimeState.step = "stopping"
	runtimeState.mut.Unlock()

	// Stop outside the lock so Ping/IsRunning/Status remain responsive while
	// the core takes time to flush and close the database.
	stopCore(app, database, cancel)

	runtimeState.mut.Lock()
	runtimeState.step = "stopped"
	runtimeState.mut.Unlock()
}

func IsRunning() bool {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	return runtimeState.app != nil
}

func IsStarting() bool {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	return runtimeState.starting
}

func GUIAddress() string {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	if runtimeState.gui == "" {
		return defaultGUIAddress
	}
	return runtimeState.gui
}

func APIKey() string {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	if runtimeState.apiKey == "" {
		return defaultAPIKey
	}
	return runtimeState.apiKey
}

func LastError() string {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	return runtimeState.lastError
}

func Status() string {
	runtimeState.mut.Lock()
	defer runtimeState.mut.Unlock()
	if runtimeState.app == nil {
		if runtimeState.lastError != "" {
			return "stopped: " + runtimeState.lastError
		}
		if runtimeState.starting {
			return "starting: " + runtimeState.step
		}
		return "stopped"
	}
	return "running since " + runtimeState.startedAt.Format(time.RFC3339)
}

func configureLocations(homeDir, syncRoot string) error {
	homeDir, err := filepath.Abs(homeDir)
	if err != nil {
		return err
	}
	if strings.TrimSpace(syncRoot) == "" {
		syncRoot = filepath.Join(homeDir, "Sync")
	}
	syncRoot, err = filepath.Abs(syncRoot)
	if err != nil {
		return err
	}
	if err := locations.SetBaseDir(locations.UserHomeBaseDir, homeDir); err != nil {
		return err
	}
	if err := locations.SetBaseDir(locations.ConfigBaseDir, homeDir); err != nil {
		return err
	}
	if err := locations.SetBaseDir(locations.DataBaseDir, homeDir); err != nil {
		return err
	}
	return locations.Set(locations.DefFolder, syncRoot)
}

// Ping verifies that the local REST API responds with the configured API key.
func Ping() bool {
	req, err := http.NewRequest(http.MethodGet, GUIAddress()+"/rest/system/ping", nil)
	if err != nil {
		return false
	}
	req.Header.Set("X-API-Key", APIKey())
	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

func DeviceID() string {
	cert, err := tls.LoadX509KeyPair(locations.Get(locations.CertFile), locations.Get(locations.KeyFile))
	if err != nil || len(cert.Certificate) == 0 {
		return ""
	}
	return protocol.NewDeviceID(cert.Certificate[0]).String()
}
