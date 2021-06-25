/*
    Sonic Heroes (And RW Studio) .ANM I/O Tool
	Original Tool by TGE.
	Export and folder loading support by Shadowth117

	Original Description below
------------------------------------------------------------------------------------------------
    Persona 3/4 Animation importer, version 1.1
    Written by TGE. Please give credit where is due.
    
    Changelog:
        1.0:
            Reads animations found in given files, and gives you a list of them to select and load represented by a GUI dialog.
            Supports reading animations from any RenderWare binary file, and .PAC files
            
        1.1:
            Reset button now properly resets the skeleton to its initial default pose.
            Note that this uses the pose the model is in when you first load an animation!
*/

ClearListener()

FileIn @"include\MaxScriptExtensions\FileStreamReader.ms"
FileIn @"include\MaxScriptExtensions\FileUtils.ms"

struct RwAnimationHeader
(
	public Version,
	public KeyFrameType,
	public FrameCount,
	public Flags,
	public Duration
)

struct RwKeyFrame
(
    public Time,
    public Rotation,
    public Translation,
    public PreviousFrameOffset,
    public PreviousFrame,
	public CurrentFrameOffset,
	public CurrentFrame,
    public Node
)

struct RwFrameSet
(
	public Node,
	public KfSet
)

struct RwCompressedKeyFrame
(
	public Time,
	public RotationX,
	public RotationY,
	public RotationZ,
	public RotationW,
	public TranslationX,
	public TranslationY,
	public TranslationZ,
	public PreviousFrameOffset
)

struct RwCompressedKeyFrameCustomData
(
	public Offset,
	public Scalar
)

struct RwAnimation
(
    public Header,
    public KeyFrames = #()
)

struct KeyValuePair
(
    public Key,
    public Value
)

global gLoader = undefined
global startup = undefined
struct RwAnimationLoader
(
	public Animations = #(),
	public AnimNames = #(),
    public FPS = 30,
    private mAnimationNodes = undefined,
    private mDefaultPose = undefined,
    
    -- Forward declarations
    public fn Create = (),
    public fn ReadAnimationsFromFile filePath = (),
    public fn ClearAnimations = (),
    public fn LoadAnimation animationIndex = (),
    public fn SelectAnimation = (),
    private fn DecompressFloat compressed = (),
    private fn GetAnimationNodes = (),
    private fn GetAnimationNodesImpl = (),
    private fn TraverseNode curNode &nodes = (),
    private fn SaveDefaultPose = (),
	
    -- Public
    public fn Create = 
    (
        gLoader = RwAnimationLoader()
        gLoader
    ),
    
	public fn ReadAnimationsFromFile filePath =
	(
        -- Read file
        local reader = FileStreamReader()
		reader.SetFile filePath false
        
        local fileType = GetFilenameType filePath
        if ( fileType == ".PAC" ) then
        (
            reader.SeekCur( 0x100 )
        )
        
        while ( ( reader.GetPosition() + 12 ) < reader.GetFileStreamLength() ) do
        (
            -- Keep looping over file until we're out of possible animations to read
            local chunkId = reader.ReadU32()
            local chunkSize = reader.ReadU32()
            local chunkVersion = reader.ReadU32()
			
			/*
			print (chunkId as string)
			print (chunkSize as string)
			print (chunkVersion as string)
			*/
            if ( chunkId != 0x1B ) then
            (
				print "chunkID != 0x1B!"
                -- Skip
                if ( ( reader.GetPosition() + chunkSize ) >= reader.GetFileStreamLength() ) then
                (
                    exit
                )
                
                reader.SeekCur( chunkSize )
                continue
            )
            
            -- Read animation
            local animation = RwAnimation()
            
            -- Read animation header
            animation.Header = RwAnimationHeader()
            animation.Header.Version = reader.ReadU32()
            animation.Header.KeyFrameType = reader.ReadU32()
            animation.Header.FrameCount = reader.ReadU32()
            animation.Header.Flags = reader.ReadU32()
            animation.Header.Duration = reader.ReadF32()
			/*
			print ("Header: " + animation.Header.Version as string)
			print ("FrameType: " + animation.Header.KeyFrameType as string)
			print ("FrameCount: " + animation.Header.FrameCount as string)
			print ("Flags: " + animation.Header.Flags as string)
			print ("Duration: " + animation.Header.Duration as string)
			*/
            -- Read keyframes
            local frameOffsets = #()
            for i = 1 to animation.Header.FrameCount do
            (
                local kf = RwKeyFrame()
                if ( animation.Header.KeyFrameType == 1 ) then
                (
                    append frameOffsets ((i - 1) * 36)
                    
                    kf.Time = reader.ReadF32()
                    kf.Rotation = reader.ReadQuatF32()
                    kf.Translation = reader.ReadVec3F32()
                    kf.PreviousFrameOffset = reader.ReadU32()
                )
                else
                (
                    append frameOffsets ((i - 1) * 24)
                    
                    local ckf = RwCompressedKeyFrame()
                    ckf.Time = reader.ReadF32()
                    ckf.RotationX = reader.ReadU16()
                    ckf.RotationY = reader.ReadU16()
                    ckf.RotationZ = reader.ReadU16()
                    ckf.RotationW = reader.ReadU16()
                    ckf.TranslationX = reader.ReadU16()
                    ckf.TranslationY = reader.ReadU16()
                    ckf.TranslationZ = reader.ReadU16()
                    ckf.PreviousFrameOffset = reader.ReadU32()
                    
                    kf.Time = ckf.Time
                    kf.Rotation = quat (DecompressFloat(ckf.RotationX)) (DecompressFloat(ckf.RotationY)) (DecompressFloat(ckf.RotationZ)) (DecompressFloat(ckf.RotationW))
                    kf.Translation = [ DecompressFloat(ckf.TranslationX), DecompressFloat(ckf.TranslationY),DecompressFloat(ckf.TranslationZ) ]
                    kf.PreviousFrameOffset = ckf.PreviousFrameOffset
                )
				
                if (kf.Time != 0.0f) then
                (
                    local prevFrameIdx = finditem frameOffsets kf.PreviousFrameOffset
					if (prevFrameIdx == 0) then
					(
						prevFrameIdx = 1
					)
                    if (prevFrameIdx != -1) then
                    (
                        kf.PreviousFrame = animation.KeyFrames[prevFrameIdx]
                    )
                    else 
                    (
                        print( "kf.PreviousFrame = undefined!! i = " + i as string + " kf.PreviousFrameOffset = " + kf.PreviousFrameOffset as string )
                        kf.PreviousFrame = undefined
                    )
                )
                else
                (
                    kf.PreviousFrame = undefined
                )
                
				--print (i as string + " " + prevFrameIdx as string)
				--print (kf as string)
				
                animation.KeyFrames[i] = kf
            )
            
            if ( animation.Header.KeyFrameType == 2 ) then
            (
                local customData = RwCompressedKeyFrameCustomData()
                customData.Offset = reader.ReadVec3F32()
                customData.Scalar = reader.ReadVec3F32()
                
                for keyFrame in animation.KeyFrames do
                (
                    keyFrame.Translation *= customData.Scalar
                    keyFrame.Translation += customData.Offset
                )
            )
            
            append Animations animation
        )
        
        reader.Close()
	),
    
    public fn LoadAnimation animationIndex =
	(
        ClearAnimations()
        
        local animation = Animations[ animationIndex ]
		
		-- set up max animation
		animationRange = interval 0 (animation.Header.Duration * FPS)
		
		-- enter animation scope
		with animate on
		(
			local boneIdx = 1
			for keyIdx = 1 to animation.Header.FrameCount do
			(
				local keyFrame = animation.KeyFrames[keyIdx]
				
				at time (keyFrame.Time * FPS)
				(
					if (keyFrame.Time == 0.0f) then
					(
						keyFrame.Node = (GetAnimationNodes())[ keyIdx ]
					)
					else if (keyFrame.Node == undefined) then
					(
						keyFrame.Node = keyFrame.PreviousFrame.Node
					)
					
                    if ( keyFrame.Node == undefined ) then
                    (
                        print( "keyFrame.Node == undefined!! keyIdx = " + keyIdx as string ) 
                    )
                    else
                    (
                        keyFrame.Node.Controller.Rotation = inverse keyFrame.Rotation
                        keyFrame.Node.Controller.Position = keyFrame.Translation
                    )
				)

			)
		)
	),
    
    public fn SelectAnimation =
    (
        rollout AnimationSelectionDialog "Select an animation" width:198 height:123
        (
        	dropdownList 'animationDropdown' "       Select an animation to load" pos:[9,7] width:176 height:40 align:#left
        	button 'OkButton' "OK" pos:[65,90] width:68 height:25 align:#left
        	spinner 'FpsSpinner' "FPS" pos:[10,58] width:56 height:16 range:[30,120,0] align:#left
        	button 'ResetButton' "Reset" pos:[118,54] width:62 height:26 align:#left
            
            fn Initialize = 
            (
                for i = 1 to gLoader.Animations.Count do
                (
                    animationDropdown.Items = append animationDropdown.Items ( gloader.AnimNames[i] )
                )
            )
            
            on FpsSpinner changed value do
            (
                gLoader.FPS = value
            )
            
        	on OkButton pressed do
        	(
        	    if ( animationDropdown.Selection != 0 ) then
        	        gLoader.LoadAnimation( animationDropdown.Selection )
        	)
            
            on ResetButton pressed do
            (
                gLoader.ClearAnimations()
            )
        )
        
        
        CreateDialog AnimationSelectionDialog
        AnimationSelectionDialog.Initialize()
    ),
        
    public fn ClearAnimations =
    (
        if ( mDefaultPose == undefined ) then
        (
            SaveDefaultPose()
        )
        else
        (
            local nodes = GetAnimationNodes()
            for node in nodes do
            (
                DeleteKeys node.Controller #allkeys
            )
            
            for i = 1 to nodes.Count do
            (
                nodes[i].Controller.Position = mDefaultPose[i][1]
                nodes[i].Controller.Rotation = mDefaultPose[i][2]
            )
        )
    ),
    
    -- Private
    private fn DecompressFloat compressed =
    (
        local floatInt = bit.shift (bit.and compressed 0x8000) 16
        if ((bit.and compressed 0x7fff) != 0) then
        (
            floatInt = bit.or floatInt ((bit.shift (bit.and compressed 0x7800) 12) + 0x38000000)
            floatInt = bit.or floatInt (bit.shift (bit.and compressed 0x07ff) 12)
        )

        bit.intasfloat floatInt
    ),
    
    private fn GetAnimationNodes =
    (
        if ( mAnimationNodes == undefined ) then
            mAnimationNodes = GetAnimationNodesImpl()
        
        return mAnimationNodes
    ),
    
    private fn GetAnimationNodesImpl =
    (
        local nodes = #()
        local nodecount = 0;
        for o in objects do
        (
            local indexProp = GetUserProp o "tag"
            if ( indexProp != undefined ) then
            (
                nodecount += 1;
                nodes[ nodecount ] = o
            )
        )
        
        if ( nodes.Count == 0 ) then
        (
            -- Fallback
            local animRootNode = GetNodeByName "_5002"
            if ( animRootNode == undefined ) then
                animRootNode = GetNodeByName "Bone2"
            
            -- Traverse nodes
            TraverseNode animRootNode &nodes
        )
        
        return nodes
    ),
    
    private fn TraverseNode curNode &nodes =
    (
        append nodes curNode
        for childNode in curNode.Children do
            TraverseNode childNode &nodes
    ),
    
    private fn SaveDefaultPose = 
    (
        mDefaultPose = #()
        
        for node in GetAnimationNodes() do
        (
            append mDefaultPose #( node.Controller.Position, node.Controller.Rotation )
        )
    )
)

fn floatCompare float1 float2 eps =
(
	test = false
	if float1 == float2 then
	( 
		test = true
	) 
	else if (abs(abs(float1) - abs(float2)) < eps) then
	(
		test = true
	) 
	
	test
)

--Relative Position Getter
fn relativePosition obj keyTime =
(
	tfm = (at time keyTime obj.transform)
	if obj.Parent != undefined then
	(
		--tfm *= (inverse (relativePosition obj.Parent keyTime)) 
		tfm *= (inverse (at time keyTime obj.Parent.transform)) 
	)
	
	tfm
)

fn RWAnimationExport ANMFile =
(
	floatEps = 0.00001
	prevOffOffset = #() --Array of offsets for previous offsets
	keyframes = #()
	
	--Grab and process keyframes
	frameCount = 0 		--Fil in with a real value on export
	unsortedFrames = #()
	maxFrames = 0
	
	--Loop through objects and gather their keyframes
	for o in objects where (getUserProp o "tag") != undefined do
	(
		posFrames = #()
		posRotFrames = #()
		posTimes = #()
		rotFrames = #()
		rotPosFrames = #()
		rotTimes = #()
		kfSet = #()
		
		if (o.position.controller.keys.count > 0) then
		(
			for itemKey in o.position.controller.keys do 
			(
				posKeyTime = itemKey.Time
				posKeyValue = ((relativePosition o itemKey.Time).translationpart)
				append posTimes posKeyTime
				append posFrames PosKeyValue
				
				--Backup rotation values
				rotKeyValue = (at time itemKey.Time (o.rotation.controller.value))
				rotKeyValue = (inverse rotKeyValue)
				append posRotFrames rotKeyValue
			)
			if (floatCompare posTimes[posTimes.count] animationrange.end floatEps) == false then --Account for if there's no end keyframe
			(
				append posTimes animationrange.end
				append posFrames ((relativePosition o animationrange.end).translationpart)
				
				--Backup rotation values
				rotKeyValue = (at time animationrange.end (o.rotation.controller.value))
				rotKeyValue = (inverse rotKeyValue)
				append posRotFrames rotKeyValue
			)
		) else  --Account for no beginning and end position frames
		(
			posKeyValue = o.pos
			posKeyValue = ((relativePosition o 0).translationpart)
			append posFrames posKeyValue
			append posTimes 0
			posKeyValue = ((relativePosition o animationrange.end).translationpart)
			append posFrames posKeyValue
			append posTimes animationrange.end
			
			--Backup rotation values
			rotKeyValue = (at time 0 (o.rotation.controller.value))
			rotKeyValue = (inverse rotKeyValue)
			append posRotFrames rotKeyValue
			rotKeyValue = (at time animationrange.end (o.rotation.controller.value))
			rotKeyValue = (inverse rotKeyValue)
			append posRotFrames rotKeyValue
		)
		
		
		--Only store keys if it has them
		if (o.rotation.controller.keys.count > 0) then
		(
			for itemKey in o.rotation.controller.keys do 
			(
				rotKeyTime = itemKey.Time
				rotKeyValue = (at time itemKey.Time (o.rotation.controller.value))
				rotKeyValue = (inverse rotKeyValue)
				append rotTimes rotKeyTime
				append rotFrames (rotKeyValue)
					
				--Backup position values
				posKeyValue = ((relativePosition o itemKey.Time).translationpart)
				append rotPosFrames PosKeyValue
			)
			if (floatCompare rotTimes[rotTimes.count] animationrange.end floatEps) == false then --Account for if there's no end keyframe
			(
				append rotTimes animationrange.end
				append rotFrames (inverse (at time animationrange.end (o.rotation.controller.value)))
					
				--Backup position values
				posKeyValue = ((relativePosition o animationrange.end).translationpart)
				append rotPosFrames PosKeyValue
			)
		) else	--Account for no beginning and end rotation frames
		(
			rotKeyValue = (at time 0 (o.rotation.controller.value))
			append rotFrames (inverse rotKeyValue)
			append rotTimes 0
			rotKeyValue = (at time animationrange.end (o.rotation.controller.value))
			append rotFrames (inverse rotKeyValue)
			append rotTimes animationrange.end
				
			--Backup position values
			posKeyValue = ((relativePosition o 0).translationpart)
			append rotPosFrames PosKeyValue
			posKeyValue = ((relativePosition o animationrange.end).translationpart)
			append rotPosFrames PosKeyValue
		)
		
		--Create Translation Frames
		for i = 1 to posFrames.count do
		(
			kf = RwKeyFrame()
			
			kf.Time = posTimes[i]
			kf.Rotation = posRotFrames[i]
			kf.Translation = posFrames[i]
			
			append kfSet kf
		)
		
		--Add Rotation Frames to Translation keyframes if times match, insert Rotation keyframes if the time doesn't exist among Translation keyframes
		for i = 1 to rotFrames.count do
		(
			bail = false
			for j = 1 to kfSet.count while bail != true do
			(
				if (floatCompare kfSet[j].Time rotTimes[i] floatEps) == true then
				(
					kfSet[j].Rotation = rotFrames[i]
					bail = true
				)
				else if(kfSet[j].Time > rotTimes[i]) then
				(
					kf = RWKeyFrame()
					kf.Time = rotTimes[i]
					kf.Rotation = rotFrames[i]
					kf.Translation = rotPosFrames[i]
					insertItem kf kfSet j
					bail = true
				)
			)
		)
		
		if(kfSet.count > maxFrames) then
		(
			maxFrames = kfSet.count
		)
		
		append unsortedFrames (RwFrameSet Node:o KfSet:kfSet)
	)
	
	--Sort Keyframes; Place frames in node sequence as long as a node has another keyframe; Handle node ids for previous offsets somehow??
	i = 1
	while i <= maxFrames do 
	(
		for j = 1 to unsortedFrames.Count do
		(
			if(i <= unsortedFrames[j].KFSet.count) then
			(
				frameCount += 1
				unsortedFrames[j].KFSet[i].CurrentFrame = frameCount
				if(i > 1) then
				(
					unsortedFrames[j].KFSet[i].PreviousFrame = unsortedFrames[j].KFSet[i-1].CurrentFrame
				)
				append keyframes unsortedFrames[j].KFSet[i]
			)
		)
		i += 1
	)
	
	frameCount = keyframes.count
	
	--Write anim
	rwANM = fopen ANMFile "wb"
	
	WriteLong rwANM 0x1B		--Chunk ID/Type? May be to differentiate from .DMA or something
	fileSizeOff = (ftell rwANM) 
	WriteLong rwANM 0x0			--File size is size of file minus 0xC. Offset stored to fill in later
	WriteLong rwANM 0x1400FFFF	--RW Version
	WriteLong rwANM 0x100		--Chunk version? Generally 256
	WriteLong rwANM 0x1         --Chunk type
	WriteLong rwANM frameCount  --Frame count
	WriteLong rwANM 0x0         --Flags, apparently. Unused for Heroes exports??
	WriteFloat rwANM (animationrange.end / framerate)
	
	--Keyframes
	for key in keyframes do
	(
		WriteFloat rwANM (key.Time / framerate) 																							-- Write Frame Timing
		WriteFloat rwANM key.Rotation.x; WriteFloat rwANM key.Rotation.y; WriteFloat rwANM key.Rotation.z; WriteFloat rwANM key.Rotation.w; --Write Rotation Data
		WriteFloat rwANM key.Translation.x; WriteFloat rwANM key.Translation.y; WriteFloat rwANM key.Translation.z; 						-- Write Translation Data
		keyframes[key.CurrentFrame].CurrentFrameOffset = (ftell rwANM) - 0x40																--Record for later
		if key.PreviousFrame != undefined then --initial frames won't have a previous frame
		(
			WriteLong rwANM keyFrames[key.PreviousFrame].CurrentFrameOffset 																--Previous frame offset
		) else
		(
			WriteLong rwANM -13579816	
		)
	)
	
	--Go back and fill offsets
	
	--Write filesize
	fileSize = (ftell rwANM) - 0xC
	fseek rwANM fileSizeOff #seek_set 
	WriteLong rwANM fileSize
	
	fflush rwANM
	fclose rwANM
)

rollout AnimWindow "Select An Option" width:155 height:90
(
	button 'FileButton' "Load Animation" align:#center
	button 'FoldButton' "Load From Folder" align:#center
	button 'ExportButton' "Export Animation" align:#center
	
	on FileButton pressed do
	(
		local filePath = FileUtils.RunOpenFileDialog "Open file containing animations" "Renderware 3D .ANM (*.ANM)|*.ANM|All Files (*.*)|*.*|" "ANM Animation Object Presets"
		if filePath != undefined then--if the user did not cancel
        (	
			local animationLoader = RwAnimationLoader.Create()
			animationLoader.ReadAnimationsFromFile( filePath )
			gLoader.LoadAnimation( 1 )
		)
	)
	
	on FoldButton pressed do
	(
		local filePath = FileUtils.RunOpenFileDialog "Open file in folder containing animations" "Renderware 3D .ANM (*.ANM)|*.ANM|All Files (*.*)|*.*|" "ANM Animation Object Presets"
		if filePath != undefined then--if the user did not cancel
        (	
			local animationLoader = RwAnimationLoader.Create()
			thePath = getFilenamePath filePath
			
			theFiles = getFiles (thePath+"\\*.ANM") --collect all ANM files in the dir.
			for objFileName = theFiles do-- go through all of them
			(
				append animationLoader.AnimNames (GetfilenameFile objFileName)
				animationLoader.ReadAnimationsFromFile( objfileName )
			)
			animationLoader.SelectAnimation()
		)
	)
	
	on ExportButton pressed do
	(
		-- Open up a dialog box
		local objFileName = getSaveFileName "Export Renderware .ANM" \
				types:"Renderware .ANM (*.ANM)|*.ANM|All Files (*.*)|*.*|"

		--Export the Animation 
		if (objFileName != undefined) then
		(
			RWAnimationExport objFileName
		)
	)
)

(
	startup = CreateDialog AnimWindow
)