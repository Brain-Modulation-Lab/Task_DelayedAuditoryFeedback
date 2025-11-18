classdef EclipseMIDIcomm
    %ECLIPSEMIDICOMM Class implements Eclipse/MIDI communication for
    %AMP research studies performed in STEPPLAB. This ver. uses the MIDI
    %communication funtionalities implemented directly on MATLAB Audio
    %System Toolbox. So, no MIDI-OX software is needed.
    %
    % Author: Manuel Diaz Cadiz, Boston University, Boston
    % Last Update: 05/07/2019
    %
    properties (Constant, Access = private)
        %   This properties define constants for by the system exclusive  
        %   format (SYSEXC) used by the EVERTIDE 4000 series. 
        %   The SYSEXC format for EVERTIDE is defined in the Technical 
        %   Note #34 provided by the manufacturer, and it follows: 
        %   ( check Tech_Note_34_MIDISyex.pdf in 
        %     R:\SteppLab\Materials\Equipment and Project Lab Resources\Eclipse Eventide )
        %
        %      <INIT> <EVENTIDE> <H4000> <id> <message_code> <lots-o-bytes> <END>
        %   
        %   Here, the following SYSEXC codes defined are:
        %    - <INIT/STOP> std. msg. begining (0xF0) & ending (0xF7) 
        %    - <EVENTIDE>/<H4000> model codes (0x1C & 0x70)
        %    - Default device <id> number (0x01)
        %    - Possible EVENTIDE/MIDI <message_codes>   
        SYSEXC_HEAD = struct( ...
                    'INIT'                , hex2byte('F0'), ... 
                    'EVERTIDE'            , hex2byte('1C'), ...
                    'H4000'               , hex2byte('70'), ... 
                    'DEVICEID'            , hex2byte('01'), ...
                    'END'                 , hex2byte('F7')  ...
                    );
        SYSEXC_MSG = struct( ...
                    'OK'                  , hex2byte('00'), ...
                    'KEYPRESS'            , hex2byte('01'), ...
                    'USEROBJECT'          , hex2byte('02'), ... 
                    'BANKCHANGE'          , hex2byte('03'), ...
                    'PROGRAM_DUMP_OLD'    , hex2byte('04'), ... % OBSOLETE / DO NOT USE
                    'SETUP_DEMP_OLD'      , hex2byte('05'), ... % OBSOLETE / DO NOT USE
                    'PROGRAM_WANT'        , hex2byte('06'), ...
                    'SETUP_WANT'          , hex2byte('07'), ...
                    'SIGFILE_DUMP'        , hex2byte('08'), ...
                    'SIGFILE_WANT'        , hex2byte('09'), ...
                    'SIGFILE_DUMP_REMOTE' , hex2byte('0A'), ...
                    'SIGFILE_WANT_QUICK'  , hex2byte('0B'), ...
                    'SIGDBASE_DUMP'       , hex2byte('0C'), ...
                    'ERROR'               , hex2byte('0D'), ...
                    'SIGDBASE_WANT'       , hex2byte('0E'), ...
                    'FILES_DUMP'          , hex2byte('0F'), ...
                    'FILES_WANT'          , hex2byte('10'), ...
                    'INTERNAL_DUMP'       , hex2byte('11'), ...
                    'INTERNAL_WANT'       , hex2byte('12'), ...
                    'CARD_DUMP'           , hex2byte('13'), ...
                    'CARD_WANT'           , hex2byte('14'), ...
                    'PROGRAM_DUMP'        , hex2byte('15'), ...
                    'SETUP_DUMP'          , hex2byte('16'), ...
                    'SCREEN_DUMP'         , hex2byte('17'), ...
                    'SCREEN_WANT'         , hex2byte('18'), ...
                    'INFO_DUMP'           , hex2byte('19'), ...
                    'INFO_WANT'           , hex2byte('1A'), ...
                    'PROGRAM_DATA'        , hex2byte('36')  ... % CURRENT CODE BUT NOT DEFINED IN THE TECH. NOTE
                    );
    end
    properties (Constant, Access = public)
        %   KEYCODE is a constant struct that contains all hexadecimal 
        %   representations of a key pressed in String format.
        %   This codes are respective to the <lots-o-bytes> field in the 
        %   SYSEXC message when the <message_code> is "SYSEXC_MSG.KEYPRESS"
        KEYCODE = struct( ...
                    'LEVELS'   , hex2byte('0F0F0F0F0F0F0F0D'), ...         % THIS IS THE VALID CODE. IT WAS WRONLY DEFINED IN TECH. NOTE
                    'BYPASS'   , hex2byte('0F0F0F0F0F0D0F0F'), ...     
                    'SOFT1'    , hex2byte('0F0B0F0F0F0F0F0F'), ...
                    'SOFT2'    , hex2byte('0F0F0F0B0F0F0F0F'), ...
                    'SOFT3'    , hex2byte('0F0F0F0F0F0B0F0F'), ...
                    'SOFT4'    , hex2byte('0F0F0F0F0F0F0F0B'), ...
                    'PROGRAM'  , hex2byte('0F070F0F0F0F0F0F'), ...
                    'SETUP'    , hex2byte('0F0F0F0F0F070F0F'), ...
                    'PATCH'    , hex2byte('0F0F0F0F0F0F0F07'), ...
                    'PARAMETER', hex2byte('0F0F0F070F0F0F0F'), ...
                    'LEFT'     , hex2byte('0F0F0F0E0F0F0F0F'), ...
                    'SELECT'   , hex2byte('0F0F0F0F0F0E0F0F'), ...
                    'RIGHT'    , hex2byte('0F0E0F0F0F0F0F0F'), ...
                    'HOTKEYS'  , hex2byte('0F0D0F0F0F0D0F0F'), ...         % THIS IS THE VALID CODE. IT WAS WRONLY DEFINED IN TECH. NOTE
                    'USER2'    , hex2byte('0F0F0F0D0F0F0F0F'), ...
                    'K1'       , hex2byte('070F0F0F0F0F0F0F'), ...
                    'K2'       , hex2byte('0F0F070F0F0F0F0F'), ...
                    'K3'       , hex2byte('0F0F0F0F070F0F0F'), ...
                    'K4'       , hex2byte('0B0F0F0F0F0F0F0F'), ...
                    'K5'       , hex2byte('0F0F0B0F0F0F0F0F'), ...
                    'K6'       , hex2byte('0F0F0F0F0B0F0F0F'), ...
                    'K7'       , hex2byte('0D0F0F0F0F0F0F0F'), ...
                    'K8'       , hex2byte('0F0F0D0F0F0F0F0F'), ...
                    'K9'       , hex2byte('0F0F0F0F0D0F0F0F'), ...
                    'K0'       , hex2byte('0F0F0E0F0F0F0F0F'), ...
                    'DOT'      , hex2byte('0E0F0F0F0F0F0F0F'), ...
                    'MINUS'    , hex2byte('0F0F0F0F0E0F0F0F'), ...
                    'UP'       , hex2byte('0F0F0F0F0F0F070F'), ...
                    'DOWN'     , hex2byte('0F0F0F0F0F0F0B0F'), ...
                    'CXL'      , hex2byte('0F0F0F0F0F0F0D0F'), ...
                    'ENTER'    , hex2byte('0F0F0F0F0F0F0E0F') ... 
                    );
    end
    properties (Hidden)
        % DEBUG_MODE is a hidden variable that controls debug messages of
        % MIDI commands. If it is true, any msg. recieve/send by the MIDI
        % is displayed on the command window.
        DEBUG_MODE = false;
    end
    properties (Access = private)
        % hMI is a handle to mididevice(). It is a private property that users 
        % should not have direct access to in the final class version. 
        hMI;
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%  PRIVATE METHODS  %%%%%%%%%%%%%%%%%%%%%%%%%%
    methods (Access = private)
        function KCodes = num2KCodeProgram(obj,Number2key) 
            % num2KCodeProgram() creates a list of KeyPress Codes depending
            % on an integer variable "Number2Key" that represent the program
            % number. "Number2Key" has to be a positive integer of 3
            % decimal digits at most
            if rem(Number2key,round(Number2key))~=0 || Number2key <0 || Number2key>999
                error('EclipseMIDIcomm: Program number has to be an integer between 1 and 999');
            end 
            KCodes  = {};
            currNum = Number2key;
                for i=3:-1:1
                    currDigit = rem(currNum,10);
                    currNum   = floor(currNum/10);
                    KCodes{i} = obj.KEYCODE.(['K' num2str(currDigit)]);
                end
        end
        function KCodes = num2KCodeValue(obj,Number2key)
            % num2KCodeValue() creates a list of KeyPress Codes depending
            % on an integer number "Number2Key" that represent signed numeric 
            % value. "Number2Key" can be positive/negative but it has to be an 
            % integer of 3 decimal digits at most
            rem_value = rem(Number2key,round(Number2key));
            if ~isnan(rem_value) && rem_value~=0 || Number2key <-999 || Number2key>999
                error('EclipseMIDIcomm: Input number has to be an integer between -999 and 999');
            end
            KCodes  = {};
            SignIDX = Number2key < 0;
            if SignIDX
                KCodes{SignIDX} = obj.KEYCODE.MINUS;
            end
            currNum = abs(Number2key);
            for i=3+SignIDX:-1:1+SignIDX
                currDigit = rem(currNum,10);
                currNum   = floor(currNum/10);
                KCodes{i} = obj.KEYCODE.(['K' num2str(currDigit)]);
            end
        end
        function KCodes = num2KCodeLevel(obj,Number2key)
            % num2KCodeLevel() creates a list of KeyPress Codes depending
            % on an number "Number2Key" that represent signed gain level 
            % value in dB, with 1 decimal point. "Number2Key" can be positive/negative 
            % but it has to be a number between -30.0 and +10.0 
            Number2key = 10*round(Number2key,1);
            rem_value = rem(Number2key,round(Number2key));
            if ~isnan(rem_value) && rem_value~=0 || Number2key <-300 || Number2key>100
                error('EclipseMIDIcomm: Input Level has to be a value between -30.0 and +10.0');
            end
            KCodes  = {};
            SignIDX = Number2key < 0;
            if SignIDX
                KCodes{SignIDX} = obj.KEYCODE.MINUS;
            end
            currNum = abs(Number2key);
                for i=4+SignIDX:-1:1+SignIDX
                    if 3+SignIDX == i
                        KCodes{i} = obj.KEYCODE.DOT;
                    else
                        currDigit = rem(currNum,10);
                        currNum   = floor(currNum/10);
                        KCodes{i} = obj.KEYCODE.(['K' num2str(currDigit)]);
                    end
                end
        end
        function KCodeName = KCode2name(obj,KCode)
            % KCode2name() returns a string with the name of the KeyPress
            % Byte array code representation, "Kcode", as input. If the code
            % does not match 8 nibbles, the string returned is '<LotOfBytes>'.
            % However, ff the code does not exist, the string returned is '<UnknownKcode>'.
            if numel(KCode) ~=8
                KCodeName = '<LotOfBytes>';
                return;
            end
            KCodeName = '<UnknownKcode>';
            fieldStr  = fieldnames(obj.KEYCODE);
            for i=1:numel(fieldStr)
                if all(KCode == obj.KEYCODE.(fieldStr{i}))
                    KCodeName = fieldStr{i};
                    break;
                end
            end   
        end
        function KCode = name2KCode(obj,KCodeName)
            % name2KCode() returns a KeyPress hexadecimal code representation 
            % of a particular Key name defined as a "KCodeName" string. 
            % If the key name does not exist, no hex. code is returned and
            % the function throws a missmatch/not found key error.
            fieldStr  = fieldnames(obj.KEYCODE);
            for i=1:numel(fieldStr)
                if strcmp(KCodeName,fieldStr{i})
                    KCode = obj.KEYCODE.(fieldStr{i});
                    return;
                end
            end   
            error(['EclipseMIDIcomm: Key name "' KCodeName '" does not exist.']);
        end
        function SysExMsgName = SysExMsg2name(obj,SysExMsg)
            % SysExCode2name() returns a string with the name of the
            % SysExMsg Byte code representation as input. If the code
            % does not exist, the string returned is '<UnknownSysExMsg>'.
            SysExMsgName = '<UnknownSysExMsg>';
            fieldStr  = fieldnames(obj.SYSEXC_MSG);
            for i=1:numel(fieldStr)
                if all(SysExMsg == obj.SYSEXC_MSG.(fieldStr{i}))
                    SysExMsgName = fieldStr{i};
                    break;
                end
            end   
        end
        function SysExHeadName = SysExHead2name(obj,SysExHead)
            % SysExHead2name() returns a string with the name of the
            % SysExHead Byte code representation as input. If the code
            % does not exist, the string returned is '<UnknownSysExHead>'.
            SysExHeadName = '<UnknownSysExHead>';
            fieldStr  = fieldnames(obj.SYSEXC_HEAD);
            for i=1:numel(fieldStr)
                if all(SysExHead == obj.SYSEXC_HEAD.(fieldStr{i}))
                    SysExHeadName = fieldStr{i};
                    break;
                end
            end   
        end
        function dispMsg__(obj,MsgArray,WayStr)
            % dispMsg() displays on the command window ONE midiMsg on a ByteArray
            % format  
            fprintf(['   ' WayStr ' ']);
            kdefined = 0;
            BYTE_STK = [];
            for i=1:numel(MsgArray)
                BYTE   = MsgArray(i);
                STR2   = reshape(dec2hex(BYTE,2)',1,[]);
                bshort = any(i == [1 2 3 4 numel(MsgArray)]);
                if bshort
                    STR1 = obj.SysExHead2name(BYTE);
                elseif i == 5
                    bshort = true;
                    STR1 = obj.SysExMsg2name(BYTE);
                    SysExMsg = STR1;
                    if strcmp(SysExMsg,'KEYPRESS')
                        MAX_BYTE_MSG = 8;
                    else 
                        MAX_BYTE_MSG = numel(MsgArray) - 6;
                    end
                elseif kdefined < MAX_BYTE_MSG
                    kdefined = kdefined + 1;
                    BYTE_STK = [BYTE_STK BYTE]; %#ok
                    if kdefined == MAX_BYTE_MSG
                        kdefined = kdefined + 1;
                        STR1 = obj.KCode2name(BYTE_STK);
                        STR2 = reshape(dec2hex(BYTE_STK,2)',1,[]);
                    end
                else
                    continue;
                end
                if kdefined ==0 || kdefined == MAX_BYTE_MSG+1
                    fprintf(['%' num2str(bshort*numel(STR1)+(~bshort)*9) 's:[%s]  '],STR1,STR2);
                end
            end
            fprintf('\n');
        end
        function dispMsg(obj,mm,WayStr)
            % dispMsg() displays on the command window the midiMsg "mm"
            % that is currently being sended/recieved by the object
            MsgArray = msg2byte(mm);
            MsgPvt   = find(MsgArray == obj.SYSEXC_HEAD.END);
            MsgPvt   = [1 MsgPvt];
            for i=1:numel(MsgPvt)-1
                obj.dispMsg__(MsgArray(MsgPvt(i):MsgPvt(i+1)),WayStr);
            end
        end
        function MidiSendMsg(obj,msg)
            % MidiSendMsg() displays & sends a midiMsg through the opened midi OUTPUT channel 
            if obj.DEBUG_MODE
                obj.dispMsg(msg,'[ MATLAB --> ECLIPSE ]');
            end
            midisend(obj.hMI,msg);
        end
        function msg = MidiRecieveMsg(obj)
            % MidiRecieveMsg() gathers & displays midiMsgs sent by the opened midi INPUT channel 
            msg = midireceive(obj.hMI);
            if obj.DEBUG_MODE
                obj.dispMsg(msg,'[ ECLIPSE --> MATLAB ]');
            end
        end
        function MidiFlush(obj)
            % MidiFlush() flushes all the internal buffer that
            % contains recieved midi messages
            midireceive(obj.hMI);
        end
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%  PUBLIC METHODS  %%%%%%%%%%%%%%%%%%%%%%%%%%
    methods (Access = public)
        function obj = EclipseMIDIcomm(device_name)
        %   EclipseMIDIcomm Class constructor. It initialize a mididevice()
        %   object to send SYSEXC messages via the MATLAB's MIDI API.
        %   The function informs current state of MIDI inputs/outputs devices
        %   as well. 
        %   There are 3 ways to initialize a EclipseMIDIcomm object, by:  
        %       a) Opening the first available MIDI device 
        %           >> obj = EclipseMIDIcomm();                    
        %       
        %       b) Opening a specific MIDI device by its string name 
        %          (it will open input & output MIDI channels at the same time 
        %           only if those channels have the same string names)
        %           >> obj = EclipseMIDIcomm('<MIDI_device_name>');
        %
        %       c) Opening specific MIDI input & output channels by their
        %          respective string names (useful when the MIDI device has different names 
        %          for MIDI input and MIDI output channels )
        %           >> obj = EclipseMIDIcomm({'<MIDI_device_input_name>','<MIDI_device_output_name>'});
            if obj.DEBUG_MODE
                mididevinfo;
            end
            if nargin < 1
                obj.hMI = mididevice(0);
            else
                if isnumeric(device_name)
                    obj.hMI = mididevice('Input',device_name(1),'Output',device_name(2));
                elseif iscell(device_name)
                    obj.hMI = mididevice('Input',device_name{1},'Output',device_name{2});
                else
                    obj.hMI = mididevice(device_name);
                end
            end
            if obj.DEBUG_MODE
                disp(obj.hMI);
            end
            pause(0.5);       
        end
        function KeyPress(obj,KCode)
        %   KeyPress() is a wrapper function to send SYSEXC_MSG.KEYPRESS messages.
        %   KCode input argument can be:
        %       a) Kcode string (hexadecimal representation, defined in KEYCODE struct)
        %       b) Text string  (the exact name of any defined field in KEYCODE struct)
        %   i.e. the 2 ways to press the ENTER key are:  
        %       a) >> obj.KeyPress(obj.KEYCODE.ENTER); 
        %       b) >> obj.KeyPress('ENTER'); 
            if ischar(KCode)
                KCode = strrep(KCode,' ','');
                KCode = obj.name2KCode(KCode);
            end
            msg = [ midimsg('SystemExclusive',0); ...
                    midimsg('Data',obj.SYSEXC_HEAD.EVERTIDE,0); ...
                    midimsg('Data',obj.SYSEXC_HEAD.H4000,0);    ...
                    midimsg('Data',obj.SYSEXC_HEAD.DEVICEID,0); ...
                    midimsg('Data',obj.SYSEXC_MSG.KEYPRESS,0); ...
                    midimsg('Data',KCode,0); ...
                    midimsg('EOX',0)];
            obj.MidiSendMsg(msg);
%             pause(0.004);
        end
        function SelectMap(obj,MapNum)
        %   SelectMap() is a wrapper function that sequences KeyPress() calls
        %   to select & load a particular MIDI Map configuration in Eclipse.
        %   MapNum input argument should be an integer between 0 and 3.
            KEYPAD_CODES = obj.num2KCodeProgram(MapNum);
            obj.KeyPress('HOTKEYS'); % CURRENT PROGRAM PAGE  
            obj.KeyPress('SETUP');   % Page 1
            obj.KeyPress('SETUP');   % Page 2
            obj.KeyPress('SETUP');   % Page 3
            obj.KeyPress('SOFT2');   % Maps -> Maps # 
            for i=1:numel(KEYPAD_CODES)
                obj.KeyPress(KEYPAD_CODES{i});
            end
            obj.KeyPress('ENTER');
            pause(2);
            obj.KeyPress('HOTKEYS'); % Go back to CURRENT PROGRAM
        end
        function LoadProgram(obj,ProgramNum)
        %   LoadProgram() is a wrapper function that sequences KeyPress() calls
        %   to select & load a particular program already stored in Eclipse.
        %   ProgramNum input argument should be an integer between 0 and 999
            KEYPAD_CODES = obj.num2KCodeProgram(ProgramNum);
            obj.KeyPress('HOTKEYS'); % CURRENT PROGRAM PAGE  
            obj.KeyPress('PROGRAM');
            for i=1:numel(KEYPAD_CODES)
                obj.KeyPress(KEYPAD_CODES{i});
            end
            obj.KeyPress('ENTER');
            obj.KeyPress('SOFT4');   % Load program (4th soft key)
%             msg = midimsg('ProgramChange',1,ProgramNum,0);
%             obj.MidiSendMsg(msg);
            pause(2);
        end
        function ProgramData = WantProgram(obj,ProgramNum)
        %   WantProgram() is a wrapper function that gets ECLIPSE ProgramData 
        %   from (a) an already loaded or (b) stored program. There are 2 call
        %   options:
        %       a) >> ProgramData = obj.WantProgram(); 
        %       b) >> ProgramData = obj.WantProgram(ProgramNum);
        %   ProgramNum input argument should be an integer between 0 and
        %   999 if it is defined. If is not, the function get the current
        %   program that's loaded in the device.
            if nargin > 1
                obj.LoadProgram(ProgramNum);
                pause(1);
            end
            obj.KeyPress('HOTKEYS'); % CURRENT PROGRAM PAGE  
            obj.KeyPress('SETUP');   % SETUP PAGE 1
            obj.KeyPress('SETUP');   % SETUP PAGE 2
            obj.KeyPress('SETUP');   % SETUP PAGE 3
            obj.KeyPress('SOFT3');   % DUMP PAGE SELECTION
            obj.MidiFlush();         % FLUSH prev. messages ( [~] = midireceive(obj.hMI) )
            obj.KeyPress('SOFT2');   % DUMP (Default: Current Program)
            pause(2);
            ProgramData = obj.MidiRecieveMsg();
            obj.KeyPress('HOTKEYS'); % GO BACK TO CURRENT PROGRAM PAGE         
        end
        function DumpProgram(obj,ProgramData)
        %   DumpProgram() sends an ECLIPSE ProgramData to be loaded 
        %   in the device. The program sent & modifies the current settings 
        %   that will be active on the device, but not permanently 
        %   (you have to manually "save as" the program later 
        %   using ECLIPSE front panel if you need to keep program changes). 
        %   ProgramData input argument is a midimsg() variable that
        %   contains Program data in a string format, identical to the
        %   WantProgram() function response. 
            msg = ProgramData;
            for j=1:numel(msg)        % Remove saved timestamps to 
                msg(j).Timestamp = 0; % avoids midi msging delays
            end
            obj.MidiSendMsg(msg);
        end
        function ProgramText = ReadProgram(~,ProgramData)
        %   ReadProgram() parses ECLIPSE ProgramData msg into readable text
        %   and displays it on the command window.
            mm = ProgramData;
            mm = cellfun(@(x) (x.MsgBytes), ...
                               mat2cell(mm,ones(1,numel(mm))),...
                               'UniformOutput',false);
            mArray = cell2mat(mm');
            DataArray = mArray(6:end-1);
            ProgramText = native2unicode(DataArray);
%             display(ProgramText);
        end
        function MainLevels(obj,IN_LVL,OUT_LVL)
        %   MainLevels() is a wrapper function that sequences KeyPress() calls
        %   to assign Levels values to the ECLIPSE MAIN Level control.
        %   IN_LVL/OUT_LVL input arguments can be scalar values
        %   from -30.0 to +10.0 dB, or 2-element vectors with level values for 
        %   left and right channels respectively.
            obj.KeyPress('HOTKEYS'); % GO TO CURRENT PROGRAM PAGE  
            obj.KeyPress('LEVELS');  % GO TO MAIN LEVEL CONTROL
            stack_LVL = {IN_LVL, OUT_LVL};
            for j=1:2
                this_LVL = stack_LVL{j};
                if j == 2
                    obj.KeyPress('SOFT2');
                end
                if numel(this_LVL) == 1
                    KEYPAD_CODES = obj.num2KCodeLevel(this_LVL);
                    for i=1:numel(KEYPAD_CODES)
                        obj.KeyPress(KEYPAD_CODES{i});
                    end
                    obj.KeyPress('ENTER');
                elseif numel(this_LVL) == 2
                    obj.KeyPress(['SOFT' num2str(j)]);
                    KEYPAD_CODES = obj.num2KCodeLevel(this_LVL(1));
                    for i=1:numel(KEYPAD_CODES)
                        obj.KeyPress(KEYPAD_CODES{i});
                    end
                    obj.KeyPress('ENTER');
                    obj.KeyPress(['SOFT' num2str(j)]);
                    KEYPAD_CODES = obj.num2KCodeLevel(this_LVL(2));
                    for i=1:numel(KEYPAD_CODES)
                        obj.KeyPress(KEYPAD_CODES{i});
                    end
                    obj.KeyPress('ENTER');
                else
                    error('EclipseMIDIcomm: IN_LVL/OUT_LVL arguments have to be scalars or 2-element vectors only!');
                end
            end 
            obj.KeyPress('SOFT1');
%             obj.KeyPress('HOTKEYS'); % GO TO CURRENT PROGRAM PAGE  
        end
        function SetValue(obj,SoftKCode,Value)
        %   SetValue() is a wrapper function that sequences KeyPress() calls
        %   to set a particular number value (signed integer) in an already 
        %   loaded program parameter, selectable by a SOFT Key.
        %   "SoftKCode" should be a respective SOFT Key code
        %   "Value"     should be an integer between -999 and 999
            if ~ischar(SoftKCode)
                SoftKCode = obj.KCode2name(SoftKCode);
            end
            if ~any(strcmpi(SoftKCode,{'SOFT4','SOFT3','SOFT2','SOFT1'}))
                error(['EclipseMIDIcomm: SoftKCode arg. ("' SoftKCode '") can '...
                       'only be a SOFT Key code.']);
            end
            KEYPAD_CODES = obj.num2KCodeValue(Value);
            obj.KeyPress(SoftKCode);
            for i=1:numel(KEYPAD_CODES)
                obj.KeyPress(KEYPAD_CODES{i});
            end
            obj.KeyPress('ENTER');
        end
        function SetLevel(obj,LevelValue)
        %   SetLevel() is a wrapper function that calls SetValue() function
        %   to set a particular level deviation value (in dB) in an already 
        %   loaded "pitch-shifter" program.
        %   LevelValue input argument should be an integer between -999 and 0
            obj.SetValue('SOFT1',LevelValue);
        end
        function SetPitch(obj,PitchValue)
        %   SetPitch() is a wrapper function that calls SetValue() function
        %   to set a particular pitch deviation value (in cents) in an already 
        %   loaded "pitch-shifter" program.
        %   PitchValue input argument should be an integer between -999 and 999
            obj.SetValue('SOFT2',PitchValue);
        end
        function SetDelay(obj,DelayValue)
        %   SetDelay() is a wrapper function that calls SetValue() function
        %   to set a particular delay value in an already 
        %   loaded "pitch-shifter" program.
        %   DelayValue input argument should be an integer between 0 and 999
            obj.SetValue('SOFT3',DelayValue);
        end
        function SetLevelMod(obj,LevelBendValue)
            if LevelBendValue>0 || LevelBendValue<-99
                error('EclipseMIDIcomm: Level Bend value should be between -99 to 0 [dB].');
            end
            % The formula below considers the real range for the ext1 mod.
            % Eclipse: External -> ext1 - Mod Wheel type (ControlChange, id=1)
            % The level mod. setup shows a unipolar range of [-128,0]
            % but "actually" Eclipse Mod/ext1 unipolar range is [-127,0]
            LevelBendValueRAW = -LevelBendValue;
            msg = midimsg('ControlChange',1,1,round(LevelBendValueRAW),0);
            obj.MidiSendMsg(msg);
        end
        function SetPitchMod(obj,PitchBendValue)
            if PitchBendValue>1000 || PitchBendValue<-1000
                error('EclipseMIDIcomm: Pitch Bend value should be between -1000 to 1000 [dB].');
            end
            % The formula below considers the real range for the ext3 mod.
            % Eclipse: External -> ext3 - Pitch Wheel type (PitchBend)
            % The level mod. setup shows a min-max range of [-1000,+1000]
            BipolarRange = 1000;
            PitchBendValueRAW = ( (16383/(2*BipolarRange))*(PitchBendValue+BipolarRange) ); 
            msg = midimsg('PitchBend',1,round(PitchBendValueRAW),0);
            obj.MidiSendMsg(msg);
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%         function SetPitchBend(obj,PitchBendValue,BipolarRange)
%             if nargin < 3
%                 BipolarRange = 1000;
%             end
%             PitchBendValue = (16383/(2*BipolarRange))*(PitchBendValue+BipolarRange);
%             PitchBendValue = max(0,min(16383,round(PitchBendValue)+1))-8;
%             msg = midimsg('PitchBend',1,PitchBendValue,0);
%             %   |-> The amount of pitch bend change to apply is in raw values 
%             %       specified as an integer in the range [0,16383]. 
%             %       The center position (no effect) is 8192.
%             %       However, Eclipse side is ranged as -1000 to 1000 (bipolar) 
%             %       for external ext3 for Pitch Wheel (Bend) Control
%             obj.MidiSendMsg(msg);
%         end
        function msg = GetPitchBendSeq(~,PitchBendValues,PitchBendTimes,BipolarRange)
            if nargin < 4
                BipolarRange = 1000;
            end
            PitchBendValues = (16383/(2*BipolarRange))*(PitchBendValues+BipolarRange);
            PitchBendValues = max(0,min(16383,round(PitchBendValues)+1))-8;
            msg = midimsg('PitchBend',1,PitchBendValues(1),PitchBendTimes(1));
            for i =2:numel(PitchBendTimes)
                msg(end+1) = midimsg('PitchBend',1,PitchBendValues(i),PitchBendTimes(i)); %#ok
            end
        end
        function SetPitchBendSeq(obj,PitchBendSeq_msg)
            obj.MidiSendMsg(PitchBendSeq_msg);
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  STATIC METHODS  %%%%%%%%%%%%%%%%%%%%%%%%%%%%
function ByteArray = hex2byte(HexStr)
    % hex2byte() transforms a hexadecimal string representation of nibble 
    % bytes into an actual byte array of nibbles. For EVERTIDE/ECLIPSE
    % devices, nibbles are pairs of hexadecimal numbers, that after this
    % transformation are translated into bytes (uint8 number format).
    ByteArray = hex2dec(reshape(strrep(HexStr,' ',''),2,[])')';
end
function ByteArray = msg2byte(Msg)
    % msg2byte() transforms a MidiMsg array representation of nibble 
    % bytes into an actual byte array of nibbles (uint8 number format).
    ByteArray = [];
    for i=1:numel(Msg)
        ByteArray = [ByteArray Msg(i).MsgBytes]; %#ok
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%