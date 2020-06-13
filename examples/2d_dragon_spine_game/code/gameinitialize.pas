{
  Copyright 2014-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Game initialization and logic. }
unit GameInitialize;

interface

uses CastleWindow;

var
  Window: TCastleWindowBase;

implementation

uses SysUtils, Math,
  CastleControls, CastleKeysMouse, CastleFilesUtils, CastleViewport,
  CastleVectors, CastleTransform, CastleSceneCore, CastleUtils, CastleColors,
  CastleUIControls, CastleMessaging, CastleGameService, CastleLog,
  CastleCameras, CastleApplicationProperties, CastleScene;

{ Google Play Games integration stuff ---------------------------------------- }

const
  { Achievement ids.
    For Android: these are generated by creating achievements in Google Developer Console.
    For iOS: these are set by you in iTunes Connect. }
  AchievementMove        = {$ifdef ANDROID} 'CgkIvIv-jrANEAIQAQ' {$else} 'move'         {$endif};
  AchievementClickFollow = {$ifdef ANDROID} 'CgkIvIv-jrANEAIQAg' {$else} 'click_follow' {$endif};
  AchievementClick3D     = {$ifdef ANDROID} 'CgkIvIv-jrANEAIQBA' {$else} 'click_3d'     {$endif};
  AchievementSeeLeft     = {$ifdef ANDROID} 'CgkIvIv-jrANEAIQBQ' {$else} 'see_left'     {$endif};
  AchievementSeeRight    = {$ifdef ANDROID} 'CgkIvIv-jrANEAIQBw' {$else} 'see_right'    {$endif};

var
  GameService: TGameService;

  { For achievements that would occur *very* often (e.g. AchievementMove
    would be submitted at every click), use a flag to not send
    GameService.Achievement more than once.

    This is only an optimization, to not overwhelm the GameService with useless calls.
    Sending the same achievement many times would be ignored anyway. }
  AchievementMoveSubmitted,
    AchievementSeeLeftSubmitted, AchievementSeeRightSubmitted: boolean;

{ main game stuff ------------------------------------------------------------ }

var
  Viewport: TCastleViewport;
  Background: TCastleScene;
  Dragon: TCastleScene;
  CameraView3D: TCastleButton;
  CameraFollowsDragon: TCastleButton;
  ShowAchievements: TCastleButton;
  DragonFlying: boolean;
  DragonFlyingTarget: TVector2;
  Status: TCastleLabel;

type
  TButtonsHandler = class
    class procedure CameraView3DClick(Sender: TObject);
    class procedure CameraFollowsDragonClick(Sender: TObject);
    class procedure ShowAchievementsClick(Sender: TObject);
  end;

const
  DragonInitialPosition: TVector3 = (Data: (2800, 800, 400));
  DragonSpeedX = 1000.0;
  DragonSpeedY =  500.0;
  DragonScale = 0.5;

procedure AddBackgroundItems;

  { Easily add a Spine animation, translated and scaled,
    and run it's animation. }
  procedure AddItem(const X, Y, Z, Scale: Single; const URL: string;
    const RunAnimation: boolean = true);
  var
    Scene: TCastleScene;
  begin
    Scene := TCastleScene.Create(Application);
    Scene.Setup2D;
    Scene.Load(URL);
    Scene.ProcessEvents := true;
    if RunAnimation then
      Scene.PlayAnimation('animation', true);
    Scene.Scale := Vector3(Scale, Scale, Scale);
    Scene.Translation := Vector3(X, Y, Z);
    { do not capture mouse picking on this item,
      otherwise Background.PointingDeviceOverItem in WindoPress would not work
      as we want, because items in front of the background would "hijack"
      mouse picks. }
    Scene.Pickable := false;
    Viewport.Items.Add(Scene);
  end;

const
  TreeZ = 200;
begin
  { z = TreeZ to place in front, only behind dragon }
  AddItem(3400, 50, TreeZ, 0.55, 'castle-data:/trees/tree1.json');
  AddItem(3400, 0, TreeZ, 0.6, 'castle-data:/trees/tree2.json');
  AddItem(1900, 10, TreeZ, 0.55, 'castle-data:/trees/tree2.json');
  AddItem(3100, 30, TreeZ, 0.66, 'castle-data:/trees/tree1.json');
  {
  for I := 0 to 1 do
    AddItem(Random * 4500, Random * 20 + 20, TreeZ + Random * 10, 0.6 + Random * 0.1, 'castle-data:/trees/tree1.json');
  for I := 0 to 1 do
    AddItem(Random * 4500, Random * 20 + 20, TreeZ + Random * 10, 0.6 + Random * 0.1, 'castle-data:/trees/tree2.json');
  }
  // AddItem(1000, 10, TreeZ, 0.65, 'castle-data:/trees/tree2.json');
  // AddItem(1000, 30, TreeZ, 0.61, 'castle-data:/trees/tree1.json');
  // AddItem(4300, 30, TreeZ, 0.7, 'castle-data:/trees/tree1.json');
  // AddItem(4600, 10, TreeZ, 0.7, 'castle-data:/trees/tree2.json');
  { z = 50 to place between background tower and background trees }
  AddItem(0,    0,  50, 1, 'castle-data:/background/clouds.json');
  AddItem(0,    0, 100, 1, 'castle-data:/background_front.x3dv', false);

  Viewport.Items.SortBackToFront2D;
end;

{ One-time initialization. }
procedure ApplicationInitialize;
const
  ButtonPadding = 30;
begin
  // Messaging.Log := true; // useful to debug what is communicated to Game Service

  GameService := TGameService.Create(nil);
  GameService.Initialize;

  Viewport := TCastleViewport.Create(Application);
  Viewport.Setup2D;
  Viewport.FullSize := true;
  Window.Controls.InsertFront(Viewport);

  { add to scene manager an X3D scene with background and trees.
    See data/background.x3dv (go ahead, open it in a text editor --- X3D files
    can be easily created and edited as normal text files) for what it does.

    This is just one way to create a background for 2D game, there are many others!
    Some alternatives: you could use a normal 2D UI for a background,
    like TCastleImageControl instead of X3D model.
    Or you could load a scene from any format --- e.g. your background
    could also be a Spine scene. }
  Background := TCastleScene.Create(Application);
  Background.Setup2D;
  Viewport.Items.Add(Background);
  Viewport.Items.MainScene := Background;
  Background.Load('castle-data:/background.x3dv');
  { not really necessary now, but in case some animations will appear
    on Background }
  Background.ProcessEvents := true;
  { this is useful to have precise collisions (not just with bounding box),
    which in turn is useful here for Background.PointingDeviceOverPoint value }
  Background.Spatial := [ssRendering, ssDynamicCollisions];
  Background.Name := 'Background'; // Name is useful for debugging

  AddBackgroundItems;

  { We always want to see full height of background.x3dv,
    we know it starts from bottom = 0.
    BoudingBox.Data[1][1] is the maximum Y value, i.e. our height.
    So projection height should adjust to background.x3dv height. }
  Viewport.Camera.Orthographic.Height := Background.BoundingBox.Data[1][1];
  Viewport.Camera.ProjectionFar := 10000;

  Dragon := TCastleScene.Create(Application);
  Dragon.Setup2D;
  Dragon.Load('castle-data:/dragon/dragon.json');
  Dragon.ProcessEvents := true;
  Dragon.Name := 'Dragon'; // Name is useful for debugging
  Dragon.DefaultAnimationTransition := 0.5;
  Dragon.PlayAnimation('idle', true);
  Dragon.Pickable := false;
  Dragon.Scale := Vector3(DragonScale, DragonScale, DragonScale);
  { translate in XY to set initial position in the middle of the screen.
    translate in Z to push dragon in front of trees
    (on Z = 20, see data/background.x3dv) }
  Dragon.Translation := DragonInitialPosition;
  Viewport.Items.Add(Dragon);

  CameraView3D := TCastleButton.Create(Window);
  CameraView3D.Caption := '3D Camera View';
  CameraView3D.OnClick := @TButtonsHandler(nil).CameraView3DClick;
  CameraView3D.Toggle := true;
  CameraView3D.Left := 10;
  CameraView3D.Bottom := 10;
  CameraView3D.PaddingHorizontal := ButtonPadding;
  CameraView3D.PaddingVertical := ButtonPadding;
  Window.Controls.InsertFront(CameraView3D);

  CameraFollowsDragon := TCastleButton.Create(Window);
  CameraFollowsDragon.Caption := 'Camera Follows Dragon';
  CameraFollowsDragon.OnClick := @TButtonsHandler(nil).CameraFollowsDragonClick;
  CameraFollowsDragon.Toggle := true;
  CameraFollowsDragon.Left := 10;
  CameraFollowsDragon.Bottom := 100;
  CameraFollowsDragon.PaddingHorizontal := ButtonPadding;
  CameraFollowsDragon.PaddingVertical := ButtonPadding;
  Window.Controls.InsertFront(CameraFollowsDragon);

  ShowAchievements := TCastleButton.Create(Window);
  ShowAchievements.Caption := 'Show Achievements (on Android or iOS)';
  ShowAchievements.OnClick := @TButtonsHandler(nil).ShowAchievementsClick;
  ShowAchievements.Left := 10;
  ShowAchievements.Bottom := 190;
  ShowAchievements.PaddingHorizontal := ButtonPadding;
  ShowAchievements.PaddingVertical := ButtonPadding;
  Window.Controls.InsertFront(ShowAchievements);

  Status := TCastleLabel.Create(Window);
  Status.Padding := 5;
  Status.Color := Red;
  Status.Left := 10;
  Status.Anchor(vpTop, -10);
  Window.Controls.InsertFront(Status);
end;

{ Looking at current state of CameraView3D.Pressed
  and CameraFollowsDragon.Pressed, calculate camera vectors. }
procedure CalculateCamera(out Pos, Dir, Up: TVector3);
const
  { Initial camera. Like initialized by TCastleViewport.Setup2D,
    but shifted to the right, to see the middle of the background scene
    where we can see the castle and dragon at initial position. }
  Camera2DPos: TVector3 = (Data: (2100, 0, 0));
  Camera2DDir: TVector3 = (Data: (0, 0, -1));
  Camera2DUp : TVector3 = (Data: (0, 1, 0));

  { Alternative camera view where it is clearly visible we are in 3D :).
    This corresponds to the initial camera 2D view above, so it is also shited
    as necessary to see the castle and dragon at initial position.
    Hint: to pick camera values experimentally, use view3dscene
    and Console->Print Current Camera.. menu item. }
  Camera3DPos: TVector3 = (Data: (329.62554931640625, 581.32476806640625, 2722.44921875));
  Camera3DDir: TVector3 = (Data: (0.6533169150352478, -0.13534674048423767, -0.7448880672454834));
  Camera3DUp : TVector3 = (Data: (0.10390279442071915, 0.99060952663421631, -0.088864780962467194));
begin
  if not CameraView3D.Pressed then
  begin
    Pos := Camera2DPos;
    Dir := Camera2DDir;
    Up  := Camera2DUp;
  end else
  begin
    Pos := Camera3DPos;
    Dir := Camera3DDir;
    Up  := Camera3DUp;
  end;

  { Apply "Camera Follows Dragon" }
  if CameraFollowsDragon.Pressed then
  begin
    Pos[0] := Dragon.Translation[0]
      { Subtract half of the screen, because camera is at the left screen corner
        when using default 2D projection (with default Camera.Orthographic.Origin = zero). }
      - 0.5 * Viewport.Camera.Orthographic.EffectiveWidth;
    { when both "Camera Follows Dragon" and "Camera 3D View" are pressed,
      we need to offset the above calculation }
    if CameraView3D.Pressed then
      Pos.Data[0] := Pos.Data[0] + (Camera3DPos[0] - Camera2DPos[0]);
  end;

  { Limit camera span, to not show blackness to the left or right.
    Note that for default 2D projection, camera is at the left corner,
    so while calculating minimum X is easy, calculating maximum X must take
    into account screen width.  }
  if not CameraView3D.Pressed then
    Pos[0] := Clamped(Pos[0],
      Background.BoundingBox.Data[0].Data[0],
      Background.BoundingBox.Data[1].Data[0] - Viewport.Camera.Orthographic.EffectiveWidth);
end;

procedure WindowUpdate(Container: TUIContainer);
var
  SecondsPassed: Single;
  T: TVector3;
  Pos, Dir, Up: TVector3;
  Camera: TCastleCamera;
begin
  Status.Caption := 'FPS: ' + Window.Fps.ToString;

  Camera := Viewport.Camera;

  { check Camera.Animation, to not mess in the middle
    of Camera.AnimateTo (we could mess it by changing Dragon now
    or by calling Camera.SetView directly) }
  if Camera.Animation then
    Exit;

  if DragonFlying then
  begin
    { update Dragon.Translation to reach DragonFlyingTarget.
      Be careful to not overshoot, and to set DragonFlying to false when
      necessary. }
    T := Dragon.Translation;
    SecondsPassed := Container.Fps.SecondsPassed;
    if T[0] < DragonFlyingTarget[0] then
      T[0] := Min(DragonFlyingTarget[0], T[0] + DragonSpeedX * SecondsPassed) else
      T[0] := Max(DragonFlyingTarget[0], T[0] - DragonSpeedX * SecondsPassed);
    if T[1] < DragonFlyingTarget[1] then
      T[1] := Min(DragonFlyingTarget[1], T[1] + DragonSpeedY * SecondsPassed) else
      T[1] := Max(DragonFlyingTarget[1], T[1] - DragonSpeedY * SecondsPassed);
    Dragon.Translation := T;

    { check did we reach the target. Note that we can compare floats
      using exact "=" operator (no need to use SameValue), because
      our Min/Maxes above make sure that we will reach the *exact* target
      at some point. }
    if (T[0] = DragonFlyingTarget[0]) and
       (T[1] = DragonFlyingTarget[1]) then
    begin
      DragonFlying := false;
      Dragon.PlayAnimation('idle', true);
    end;

    if (T[0] < 1000) and not AchievementSeeLeftSubmitted then
    begin
      GameService.Achievement(AchievementSeeLeft);
      AchievementSeeLeftSubmitted := true;
    end;
    if (T[0] > 7000) and not AchievementSeeRightSubmitted then
    begin
      GameService.Achievement(AchievementSeeRight);
      AchievementSeeRightSubmitted := true;
    end;
  end;

  { move camera, in case CameraFollowsDragon.Pressed.
    Do it in every update, to react to window resize and to Dragon
    changes. }
  CalculateCamera(Pos, Dir, Up);
  Camera.SetView(Pos, Dir, Up);
end;

procedure WindowPress(Container: TUIContainer; const Event: TInputPressRelease);
var
  S: TVector3;
  WorldPosition: TVector3;
begin
  if Event.IsKey(K_F5) then
    Window.Container.SaveScreenToDefaultFile;
  if Event.IsKey(K_Escape) then
    Application.Terminate;

  if Event.IsMouseButton(mbLeft) then
  begin
    if Viewport.PositionToWorldPlane(Event.Position, true, 0, WorldPosition) then
    begin
      if not DragonFlying then
        Dragon.PlayAnimation('flying', true);
      DragonFlying := true;
      DragonFlyingTarget := WorldPosition.XY;

      { force scale in X to be negative or positive, to easily make
        flying left/right animations from single "flying" animation. }
      S := Dragon.Scale;
      if DragonFlyingTarget[0] > Dragon.Translation[0] then
        S[0] := -Abs(S[0]) else
        S[0] := Abs(S[0]);
      Dragon.Scale := S;

      if not AchievementMoveSubmitted then
      begin
        GameService.Achievement(AchievementMove);
        AchievementMoveSubmitted := true;
      end;
    end;
  end;
end;

class procedure TButtonsHandler.CameraView3DClick(Sender: TObject);
var
  Pos, Dir, Up: TVector3;
begin
  if not Viewport.Camera.Animation then { do not mess when Camera.AnimateTo is in progress }
  begin
    CameraView3D.Pressed := not CameraView3D.Pressed;
    CalculateCamera(Pos, Dir, Up);
    Viewport.Camera.AnimateTo(Pos, Dir, Up, 1.0);
    GameService.Achievement(AchievementClick3D);
  end;
end;

class procedure TButtonsHandler.CameraFollowsDragonClick(Sender: TObject);
var
  Pos, Dir, Up: TVector3;
begin
  if not Viewport.Camera.Animation then { do not mess when Camera.AnimateTo is in progress }
  begin
    CameraFollowsDragon.Pressed := not CameraFollowsDragon.Pressed;
    CalculateCamera(Pos, Dir, Up);
    Viewport.Camera.AnimateTo(Pos, Dir, Up, 1.0);
    GameService.Achievement(AchievementClickFollow);
  end;
end;

class procedure TButtonsHandler.ShowAchievementsClick(Sender: TObject);
begin
  GameService.ShowAchievements;
end;

initialization
  { Set ApplicationName early, as our log uses it. }
  ApplicationProperties.ApplicationName := 'castle_spine';

  InitializeLog;

  { initialize Application callbacks }
  Application.OnInitialize := @ApplicationInitialize;

  { create Window and initialize Window callbacks }
  Window := TCastleWindowBase.Create(Application);
  Window.OnPress := @WindowPress;
  Window.OnUpdate := @WindowUpdate;
  Window.FpsShowOnCaption := true;
  Application.MainWindow := Window;

  OptimizeExtensiveTransformations := true;
finalization
  FreeAndNil(GameService);
end.
