# O3D Viewer – Windows / Tauri csomag

Ez egy **Tauri 2** Windows-wrapper az [Online3DViewer](https://github.com/kovacsv/Online3DViewer) 0.18.0 kiadásához.

## Mit csinál?

- Natív Windows ablakban fut, nem külön böngészőfülön.
- A teljes upstream kezelőfelületet használja: drag-and-drop, fájlmegnyitás, model-info és export.
- A build során a forrásból elkészül a helyi, beágyazott frontend; futás közben nincs szüksége webszerverre.
- Támogatott import többek között: 3DM, 3DS, 3MF, AMF, BIM, BREP, DAE, FBX, FCStd, glTF/GLB, IFC, IGES, STEP, STL, OBJ, OFF, PLY, WRL.

## Windows build

Előfeltétel: Node.js LTS, Rust (MSVC toolchain), valamint a Visual Studio C++ Build Tools / Windows SDK.

```powershell
npm install
npm run tauri build
```

Az első build letölti és elkészíti az Online3DViewer **0.18.0** frontendjét. Az elkészült NSIS telepítő itt lesz:

```text
src-tauri\target\release\bundle\nsis\
```

## Megjegyzés a méretről

A kis `o3dv.min.js` csomag önmagában csak az engine. A teljes offline változat tartalmazza az upstream `libs` könyvtárat is (CAD-importerek, WASM komponensek), ezért a végleges telepítő várhatóan **15–20 MB**.

## Licencek

Az Online3DViewer MIT licencű. A build belehelyezi az eredeti `LICENSE.md` fájlt a beágyazott frontend mellé `ONLINE3DVIEWER_LICENSE.md` néven.
