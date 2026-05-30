port module Ports exposing
    ( canInstall, clearAllStorage, clearStorage, downloadFile
    , extractExifGps, gotExifResult, gotGpsCoords
    , nativeShare, nativeShareResult, networkStatus, notificationState
    , ocrImagePrepared, pouchIn, pouchOut, prepareOcrImage, pushSubscribeResult
    , requestGeolocation, savePushPrefs, saveStorage, scanProxyIn, scanProxyOut
    , startSync, stopSync, subscribePush, trackFunnel, triggerInstallPrompt
    , unsubscribePush, verifyResults
    )

{-| Every JavaScript interop port for the app, extracted from `Main.elm`
so feature modules (e.g. `Page.Scan`) can call the ports they need
without depending on `Main`. The set is unchanged from when these lived
in `Main`; only their home moved (#368).

@docs canInstall, clearAllStorage, clearStorage, downloadFile
@docs extractExifGps, gotExifResult, gotGpsCoords
@docs nativeShare, nativeShareResult, networkStatus, notificationState
@docs ocrImagePrepared, pouchIn, pouchOut, prepareOcrImage, pushSubscribeResult
@docs requestGeolocation, savePushPrefs, saveStorage, scanProxyIn, scanProxyOut
@docs startSync, stopSync, subscribePush, trackFunnel, triggerInstallPrompt
@docs unsubscribePush, verifyResults

-}

import Json.Decode
import Json.Encode


port saveStorage : { key : String, value : String } -> Cmd msg


port clearStorage : () -> Cmd msg


port clearAllStorage : () -> Cmd msg


port pouchOut : Json.Decode.Value -> Cmd msg


port pouchIn : (Json.Decode.Value -> msg) -> Sub msg


port startSync : Json.Decode.Value -> Cmd msg


port stopSync : () -> Cmd msg


port requestGeolocation : () -> Cmd msg


port extractExifGps : { id : String, dataUrl : String } -> Cmd msg


port prepareOcrImage : { dataUrl : String, id : String, maxBytes : Int } -> Cmd msg


port ocrImagePrepared : ({ dataUrl : String, error : String, finalBytes : Int, id : String, originalBytes : Int } -> msg) -> Sub msg


port gotGpsCoords : ({ lat : Float, lon : Float, denied : Bool } -> msg) -> Sub msg


port gotExifResult : ({ id : String, lat : Float, lon : Float, hasGps : Bool, debug : String } -> msg) -> Sub msg


port networkStatus : (Bool -> msg) -> Sub msg


port triggerInstallPrompt : () -> Cmd msg


port canInstall : (Bool -> msg) -> Sub msg


port scanProxyOut : { backendUrl : String, body : Json.Encode.Value, itemId : String } -> Cmd msg


port scanProxyIn : ({ body : String, itemId : String, ok : Bool, status : Int } -> msg) -> Sub msg


port savePushPrefs : Json.Decode.Value -> Cmd msg


port subscribePush : { prefs : Json.Decode.Value, vapidPublicKey : String } -> Cmd msg


port unsubscribePush : () -> Cmd msg


port notificationState : ({ permission : String, prefs : Json.Decode.Value, standalone : Bool, subscribed : Bool } -> msg) -> Sub msg


port pushSubscribeResult : ({ error : String, ok : Bool } -> msg) -> Sub msg


port downloadFile : { content : String, filename : String, mimeType : String } -> Cmd msg


port nativeShare : { mode : String, text : String, title : String, url : String } -> Cmd msg


port nativeShareResult : ({ ok : Bool, reason : String } -> msg) -> Sub msg


{-| Fire-and-forget funnel analytics beacon (#340). Payload is
`{ stage, flockId }` — see `Analytics.elm` for the stage allowlist.
The JS handler POSTs to `/invite/track` (no auth, no PII).
-}
port trackFunnel : { flockId : String, stage : String } -> Cmd msg


{-| Push the full verification matrix to JS so the `/verify` routes can expose
`window.__verify`. Fired only when booting into a `RouteVerify` URL. See
`Verify.Registry` and the Verify track plan.
-}
port verifyResults : Json.Encode.Value -> Cmd msg
