package main

import (
	"os"

	"github.com/DeepInThought/deepbeat/cmd"

	_ "github.com/DeepInThought/deepbeat/include"
)

func main() {
	if err := cmd.RootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
