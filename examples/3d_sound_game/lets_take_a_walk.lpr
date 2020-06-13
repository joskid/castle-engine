{
  Copyright 2003-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Walk around the 3D world with 3D sound attached to objects.

  History: This demo was a first test of using OpenAL with our game engine,
  done on 2003-11, attaching sounds to various moving 3D objects.
  It was also the first (and the last, for now) program where I used lightmaps
  generated by our own genLightMap --- the point was to bake shadows
  on the ground texture base_shadowed.png.
  It was modified many times since then, to simplify and take advantage of TCastleTransform,
  TCastleViewport and many other CGE features.

  If you'd like to improve it, here are some ideas (TODOs):
  - add collisions between rat and tnts and level main scene
  - more interesting rat movement track. Maybe use AI from CastleCreatures.
  - more elaborate level (initially, some house and more lamps were planned)
  - better rat sound
}

program lets_take_a_walk;

uses SysUtils, Classes,
  CastleWindow, CastleScene, X3DFields, X3DNodes, CastleColors,
  CastleUtils, CastleGLUtils, CastleBoxes, CastleVectors,
  CastleProgress, CastleWindowProgress, CastleStringUtils,
  CastleParameters, CastleImages, CastleMessages, CastleFilesUtils, CastleGLImages,
  CastleTransform, CastleSoundEngine, CastleRectangles,
  CastleControls, CastleConfig, CastleKeysMouse, CastleControlsImages,
  CastleViewport, CastleCameras;

{ global variables ----------------------------------------------------------- }

var
  Window: TCastleWindowBase;
  Viewport: TCastleViewport;
  Navigation: TCastleWalkNavigation;

  TntScene, Rat, Level: TCastleScene;
  RatAngle: Single;

  stRatSound, stRatSqueak, stKaboom, stCricket: TSoundType;
  RatSound: TSound;

  HelpMessage: TCastleLabel;
  MuteImage: TCastleImageControl;
  Crosshair: TCastleCrosshair;

{ TNT ------------------------------------------------------------------------ }

type
  TTnt = class(TCastleTransform)
  private
    ToRemove: boolean;
  public
    function PointingDeviceActivate(const Active: boolean;
      const Distance: Single; const CancelAction: boolean = false): boolean; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

const
  { Max number of TNT items. Be careful with increasing this,
    too large values may cause FPS to suffer. }
  MaxTntsCount = 40;
var
  TntsCount: Integer = 0;

function TTnt.PointingDeviceActivate(const Active: boolean;
  const Distance: Single; const CancelAction: boolean): boolean;
begin
  Result := Active and (not ToRemove) and (not CancelAction);
  if not Result then Exit;

  SoundEngine.Sound3D(stKaboom, Translation);
  if PointsDistanceSqr(Translation, Rat.Translation) < 1.0 then
    SoundEngine.Sound3D(stRatSqueak, Rat.Translation);

  ToRemove := true;
  Dec(TntsCount);
end;

procedure TTnt.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
var
  T: TVector3;
begin
  inherited;

  { make gravity }
  T := Translation;
  if T.Data[2] > 0 then
  begin
    T.Data[2] := T.Data[2] - (5 * SecondsPassed);
    MaxVar(T.Data[2], 0);
    Translation := T;
  end;

  if ToRemove then
    RemoveMe := rtRemoveAndFree;
end;

procedure NewTnt(Z: Single);
var
  TntSize: Single;
  Tnt: TTnt;
  Box: TBox3D;
begin
  TntSize := TntScene.BoundingBox.MaxSize;
  Tnt := TTnt.Create(Application);
  Tnt.Add(TntScene);
  Box := Level.BoundingBox;
  Tnt.Translation := Vector3(
    RandomFloatRange(Box.Data[0].Data[0], Box.Data[1].Data[0]-TntSize),
    RandomFloatRange(Box.Data[0].Data[1], Box.Data[1].Data[1]-TntSize),
    Z);
  Viewport.Items.Add(Tnt);
  Inc(TntsCount);
end;

{ some functions ------------------------------------------------------------- }

{ update Rat.Translation based on RatAngle }
procedure UpdateRatPosition;
const
  RatCircleMiddle: TVector3 = (Data: (0, 0, 0));
  RatCircleRadius = 3;
var
  T: TVector3;
begin
  T := RatCircleMiddle;
  T.Data[0] := T.Data[0] + (Cos(RatAngle) * RatCircleRadius);
  T.Data[1] := T.Data[1] + (Sin(RatAngle) * RatCircleRadius);
  Rat.Translation := T;
end;

type
  TDummy = class
    class procedure CameraChanged(Camera: TObject);
  end;

class procedure TDummy.CameraChanged(Camera: TObject);
{ Update stuff based on whether camera position is inside mute area. }

  function CylinderContains(const P: TVector3;
    const MiddleX, MiddleY, Radius, MinZ, MaxZ: Single): boolean;
  begin
    Result :=
      (Sqr(P[0]-MiddleX) + Sqr(P[1]-MiddleY) <= Sqr(Radius)) and
      (MinZ <= P[2]) and (P[2] <= MaxZ);
  end;

var
  InMuteArea: boolean;
begin
  InMuteArea := CylinderContains(Viewport.Camera.Position, 2, 0, 0.38, 0, 1.045640);

  if MuteImage <> nil then
    MuteImage.Exists := InMuteArea;

  if InMuteArea then
    SoundEngine.Volume := 0
  else
    SoundEngine.Volume := 1;
end;

{ help message --------------------------------------------------------------- }

const
  Version = '1.2.4';
  DisplayApplicationName = 'lets_take_a_walk';

{ window callbacks ----------------------------------------------------------- }

procedure Update(Container: TUIContainer);
begin
  { update rat }
  RatAngle := RatAngle + (0.5 * Window.Fps.SecondsPassed);
  UpdateRatPosition;
  if RatSound <> nil then
    RatSound.Position := Rat.Translation;
end;

procedure Timer(Container: TUIContainer);
begin
  while TntsCount < MaxTntsCount do NewTnt(3.0);
end;

procedure Press(Container: TUIContainer; const Event: TInputPressRelease);
begin
  if Event.EventType = itKey then
    case Event.Key of
      K_T : (Level.Event('MyScript', 'forceThunderNow') as TSFBoolEvent).Send(true);
      K_F1: HelpMessage.Exists := not HelpMessage.Exists;
      K_F4:
        begin
          Navigation.MouseLook := not Navigation.MouseLook;
          // crosshair makes sense only with mouse look
          Crosshair.Exists := Navigation.MouseLook;
        end;
      K_F5: Window.Container.SaveScreenToDefaultFile;
    end;
end;

{ parsing parameters --------------------------------------------------------- }

const
  Options: array[0..1]of TOption =
  ((Short:'h'; Long: 'help'; Argument: oaNone),
   (Short:'v'; Long: 'version'; Argument: oaNone)
  );

procedure OptionProc(OptionNum: Integer; HasArgument: boolean;
  const Argument: string; const SeparateArgs: TSeparateArgs; Data: Pointer);
begin
  case OptionNum of
    0:begin
        InfoWrite(
          'lets_take_a_walk: a toy, demonstrating the use of VRML/X3D and OpenGL rendering' +nl+
          '  and OpenAL environmental audio combined in one simple program.' +nl+
          '  You can walk in a 3D world (with collision-checking) using DOOM-like' +nl+
          '  keys (Up/Down, Right/Left, PageUp/PageDown, Insert/Delete, Home, +/-),' +nl+
          '  you can fire up some TNTs etc. Nothing special - but I hope that' +nl+
          '  such combination of 3d graphic and sound will make a nice effect.' +nl+
          nl+
          'Options:' +nl+
          HelpOptionHelp +nl+
          VersionOptionHelp +nl+
          SoundEngine.ParseParametersHelp +nl+
          nl+
          TCastleWindowBase.ParseParametersHelp(StandardParseOptions, true) +nl+
          nl+
          SCastleEngineProgramHelpSuffix(DisplayApplicationName, Version, true));
        Halt;
      end;
    1:begin
        Writeln(Version);
        Halt;
      end;
  end;
end;

{ main -------------------------------------------------------------------- }

begin
  { load config, before SoundEngine.ParseParameters
    (that may change SoundEngine.Enable by --no-sound). }
  UserConfig.Load;
  SoundEngine.LoadFromConfig(UserConfig);

  { init messages }
  Theme.Images[tiWindow] := WindowDarkTransparent;

  { init window }
  Window := TCastleWindowBase.Create(Application);
  Window.OnUpdate := @Update;
  Window.OnTimer := @Timer;
  Window.OnPress := @Press;
  Window.AutoRedisplay := true;
  Window.Caption := 'Let''s take a walk';
  Window.SetDemoOptions(K_F11, CharEscape, true);

  { parse parameters }
  Window.FullScreen := true; { by default we open in fullscreen }
  Window.ParseParameters(StandardParseOptions);
  SoundEngine.ParseParameters;
  Parameters.Parse(Options, @OptionProc, nil);

  { open window }
  Window.Open;

  { init progress }
  Application.MainWindow := Window;
  Progress.UserInterface := WindowProgressInterface;

  { init Viewport }
  Viewport := TCastleViewport.Create(Application);
  Viewport.FullSize := true;
  Viewport.AutoCamera := true;
  Viewport.PreventInfiniteFallingDown := true;
  Window.Controls.InsertFront(Viewport);

  Viewport.OnCameraChanged := @TDummy(nil).CameraChanged;

  { If you want to make shooting (which is here realized by picking) easier,
    you can use
      Viewport.ApproximateActivation := true;
    This could be nice for an "easy" difficulty level of the game.
    Note that many games use picking for interacting with 3D objects,
    not for shooting, and then "ApproximateActivation := true" may
    be applicable always (for any difficulty level). }

  { init Navigation }
  Navigation := TCastleWalkNavigation.Create(Application);
  Navigation.PreferredHeight := 0.56;
  Navigation.Radius := 0.05;
  Navigation.MoveSpeed :=  10;
  Viewport.Navigation := Navigation;

  { init MuteImage. Before loading level, as loading level initializes camera
    which already causes MuteImage update. }
  MuteImage := TCastleImageControl.Create(Application);
  MuteImage.URL := 'castle-data:/textures/mute_sign.png';
  MuteImage.Anchor(hpRight, -20);
  MuteImage.Anchor(vpTop, -20);
  MuteImage.Exists := false; // don't show it initially
  Window.Controls.InsertFront(MuteImage);

  Crosshair := TCastleCrosshair.Create(Application);
  Crosshair.Exists := false;
  Window.Controls.InsertFront(Crosshair);

  HelpMessage := TCastleLabel.Create(Application);
  HelpMessage.Caption :=
    'Movement:' + NL +
    '  Arrow keys = move and rotate' + NL +
    '  Space = jump' + NL +
    '  C = crouch' + NL +
    '  See the rest of view3dscene key shortcuts.' + NL +
    '' + NL +
    'Other:' + NL +
    '  F1 = toggle this help' + NL +
    '  F4 = toggle mouse look' + NL +
    '  F5 = save screen to file lets_take_a_walk_<int>.png' + NL +
    '  F11 = toggle fullscreen mode' + NL +
    '  Escape = exit';
  HelpMessage.Anchor(hpLeft, 10);
  HelpMessage.Anchor(vpTop, -10);
  HelpMessage.Frame := true;
  HelpMessage.FrameColor := Vector4(0.25, 0.25, 0.25, 1);
  HelpMessage.Padding := 10;
  HelpMessage.Color := White;
  Window.Controls.InsertFront(HelpMessage);

  { init level }
  Level := TCastleScene.Create(Application);
  Level.Load('castle-data:/levels/base_level_final.x3dv');
  Level.Spatial := [ssRendering, ssDynamicCollisions];
  Level.ProcessEvents := true;
  Viewport.Items.Add(Level);
  Viewport.Items.MainScene := Level;

  { init Rat }
  Rat := TCastleScene.Create(Application);
  Rat.Load('castle-data:/3d/rat.x3d');
  Viewport.Items.Add(Rat);
  UpdateRatPosition;

  { init Tnt }
  TntScene := TCastleScene.Create(Application);
  TntScene.Load('castle-data:/3d/tnt.wrl');
  while TntsCount < MaxTntsCount do NewTnt(0.0);

  { init 3D sounds }
  SoundEngine.RepositoryURL := 'castle-data:/sounds/index.xml';
  SoundEngine.DistanceModel := dmInverseDistanceClamped; //< OpenAL default
  stRatSound  := SoundEngine.SoundFromName('rat_sound');
  stRatSqueak := SoundEngine.SoundFromName('rat_squeak');
  stKaboom    := SoundEngine.SoundFromName('kaboom');
  stCricket   := SoundEngine.SoundFromName('cricket');
  RatSound := SoundEngine.Sound3D(stRatSound, Rat.Translation, true);
  SoundEngine.Sound3D(stCricket, Vector3(2.61, -1.96, 1), true);

  Application.Run;
end.
