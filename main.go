package main

import (
	"os"

	"github.com/DeepInThought/deepbeats/cmd"
)

func main() {
	if err := cmd.RootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
