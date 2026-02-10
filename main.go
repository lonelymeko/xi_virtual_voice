package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	"github.com/wailsapp/wails/v2/pkg/options/windows"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	// Create an instance of the app structure
	app := NewApp()

	// Create application with options
	err := wails.Run(&options.App{
		Title:       "TTS 虚拟麦克风",
		Width:       260,
		Height:      250,
		MinWidth:    260,
		MinHeight:   250,
		MaxWidth:    600,
		MaxHeight:   800,
		AlwaysOnTop: false,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 245, G: 245, B: 245, A: 1},
		OnStartup:        app.startup,
		Mac: &mac.Options{
			TitleBar: &mac.TitleBar{
				// 透明
				TitlebarAppearsTransparent: true,
				// 隐藏标题
				HideTitle: true,
				// 隐藏标题栏
				HideTitleBar: false,
				// 全屏
				FullSizeContent: false,
				// 显示工具栏
				UseToolbar: true,
				// 隐藏工具栏分隔符
				HideToolbarSeparator: false,
			},
		},
		Windows: &windows.Options{
			WebviewIsTransparent: false,
			WindowIsTranslucent:  false,
			DisableWindowIcon:    false,
			Theme:                windows.SystemDefault,
		},
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
