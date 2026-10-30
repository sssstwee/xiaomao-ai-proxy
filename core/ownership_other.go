//go:build !(darwin || linux) || android || openharmony

package core

func initOwnership(homeDir string) {}

func scheduleReclaimOwnership() {}

func reclaimDirOwnership(path string) {}
