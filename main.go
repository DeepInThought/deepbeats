package main

import (
	"os"

	"github.com/DeepInThought/deepbeats/cmd"

	_ "github.com/DeepInThought/deepbeats/include"
)

func main() {
	if err := cmd.RootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
