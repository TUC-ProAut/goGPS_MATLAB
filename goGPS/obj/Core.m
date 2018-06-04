%   CLASS Core
% =========================================================================
%
% DESCRIPTION
%   Collector of settings to manage a useful parameters of goGPS
%   This singleton class collects multiple objects containing various
%   parameters
%
% EXAMPLE
%   core = Core();
%
% FOR A LIST OF CONSTANTs and METHODS use doc Core


%--------------------------------------------------------------------------
%               ___ ___ ___
%     __ _ ___ / __| _ | __
%    / _` / _ \ (_ |  _|__ \
%    \__, \___/\___|_| |___/
%    |___/                    v 0.6.0 alpha 2 - nightly
%
%--------------------------------------------------------------------------
%  Copyright (C) 2009-2018 Mirko Reguzzoni, Eugenio Realini
%  Written by:       Gatti Andrea
%  Contributors:     Gatti Andrea, ...
%  A list of all the historical goGPS contributors is in CREDITS.nfo
%--------------------------------------------------------------------------
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
%--------------------------------------------------------------------------
% 01100111 01101111 01000111 01010000 01010011
%--------------------------------------------------------------------------

classdef Core < handle

    %% PROPERTIES CONSTANTS
    % ==================================================================================================================================================
    properties (Constant)
        GO_GPS_VERSION = '0.6.0 alpha 2 - nightly';
        GUI_MODE = 0; % 0 means text, 1 means GUI, 5 both
    end

    %% PROPERTIES SINGLETON POINTERS
    % ==================================================================================================================================================
    properties % Utility Pointers to Singletons
        log
        gc
        state
        w_bar
        sky
        cmd
    end

    %% PROPERTIES RECEIVERS
    % ==================================================================================================================================================
    properties % Utility Pointers to Singletons
        rec      % List of all the receiver used in a session
        
        rec_list % List of all the receiver used in all the session
    end

    %% METHOD CREATOR
    % ==================================================================================================================================================
    methods (Static, Access = private)
        % Concrete implementation.  See Singleton superclass.
        function this = Core(force_clean)
            if nargin < 1
                force_clean = false;
            end
            % Core object creator
            this.log = Logger.getInstance();
            this.init(force_clean);            
        end
    end
    
    %% METHODS UI
    % ==================================================================================================================================================
    methods (Static, Access = public)
        function this = getInstance(force_clean)
            if nargin < 1
                force_clean = false;
            end
            % Get the persistent instance of the class
            persistent unique_instance_core__

            if isempty(unique_instance_core__)
                this = Core(force_clean);
                unique_instance_core__ = this;
            else
                this = unique_instance_core__;
                this.init(force_clean);
            end
            
        end

        function ok_go = openGUI()
            ok_go = gui_goGPS;
        end
    end
    
    %% METHODS INIT
    % ==================================================================================================================================================
    methods
        function init(this, force_clean)
            % Get instances for:
            %   - Global_Configuration
            %   - Settings
            %   - Wait_Bar
            %   - Sky
            %   - Command_Interpreter
            %
            % SYNTAX:
            %   this.init(<force_clean>)
            
            if nargin < 2
                force_clean = false;
            end
            this.log.setColorMode(true);
            Core_UI.showTextHeader();
            fclose('all');
            this.gc = Global_Configuration.getInstance();
            this.state = Global_Configuration.getCurrentSettings();
            this.w_bar = Go_Wait_Bar.getInstance(100,'Welcome to goGPS', Core.GUI_MODE);  % 0 means text, 1 means GUI, 5 both
            this.sky = Core_Sky.getInstance(force_clean);
            this.cmd = Command_Interpreter.getInstance;            
        end
        
        function import(this, state)
            % Import Settings from ini files
            % 
            % INPUT:
            %   state       can be a string to the path of the settings file
            %               or a state object
            %
            % SYNTAX:
            %   this.import(state)
            
            if ischar(state)
                this.importIniFile(state);
            else
                this.importState(state);
            end
        end
            
        function importIniFile(this, ini_settings_file)
            % Import Settings from ini files
            %
            % SYNTAX:
            %   this.importIniFile(ini_settings_file)
            if  exist(ini_settings_file, 'file')
                this.importIniFile(ini_settings_file);
            end
        end
        
        function importState(this, state)
            % Import Settings from state
            %
            % SYNTAX:
            %   this.importState(state)
            
            this.state.import(state);
        end
        
        function prepareProcessing(this, flag_rem_check)
            % Init settings, and download necessary files
            %
            % SYNTAX:
            %   this.prepareProcessing(flag_rem_check)
            if nargin == 2
                this.state.setRemCheck(flag_rem_check);
            end
            
            this.log.newLine();
            this.log.addMarkedMessage(sprintf('PROJECT: %s', this.state.getPrjName()));

            this.gc.initConfiguration(); % Set up / download observations and navigational files
            this.log.addMarkedMessage('Conjuring all the files!');
            fw = File_Wizard;
            c_mode = this.log.getColorMode();
            this.log.setColorMode(0);
            if this.state.getRemCheck()
                fw.conjureFiles();
            end
            this.log.setColorMode(c_mode);
        end
    end
    
    %% METHODS RUN
    % ==================================================================================================================================================
    methods
        function prepareSession(this, session_number)
            % Check the time-limits for the files in the session
            % Init the Sky and Meteo object
            %
            % SYNTAX
            %   this.prepareSession(session_number)
            
            session = session_number;
            
            this.log.newLine;
            this.log.simpleSeparator();
            this.log.addMessage(sprintf('Starting session %d of %d', session, this.state.getSessionCount()));
            this.log.simpleSeparator();
                      
            clear rec;  % handle to all the receivers
            this.log.newLine();
            for r = 1 : this.state.getRecCount()
                this.log.addMarkedMessage(sprintf('Preparing receiver %d of %d', r, this.state.getRecCount()));
                
                rec(r) = Receiver(this.state.getConstellationCollector(), this.state.getRecPath(r, session), this.state.getDynMode(r)); %#ok<AGROW>
            end
            this.rec = rec;
            this.log.newLine();            

            % Init Meteo and Sky objects
            [~, time_lim_large] = Core.getRecTimeSpan(session);
            this.initSkySession(time_lim_large);
            this.log.newLine();
            this.initMeteoNetwork(time_lim_large);            
            this.log.simpleSeparator();     
            
            % inti atmo object
            if this.state.isVMF()
                atmo = Atmosphere.getInstance();
                atmo.initVMF(time_lim_large.first,time_lim_large.last);
            end
            
        end  
        
        function initSkySession(this, time_lim)
            % Init sky for this session
            this.sky = Core_Sky.getInstance();
            this.sky.initSession(time_lim.first, time_lim.last);
        end
        
        function initMeteoNetwork(this, time_lim)
            % Init the meteo network            
            mn = Meteo_Network.getInstance();
            mn.initSession(time_lim.first, time_lim.last);            
        end
        
        function go(this, session_num)
            % Run a session and execut the command list in the settings
            %
            % SYNTAX
            %   this.go(session_num)
            
            t0 = tic;
            this.rec_list = [];
            if nargin == 1
                session_list = 1 : this.state.getSessionCount();
            else
                session_list = session_num;
            end
            % init refererecne frame object
            rf = Core_Reference_Frame.getInstance();
            rf.init();
            for s = session_list
                this.prepareSession(s);
                this.cmd.exec(this.rec);
                                
                if this.state.isKeepRecList()
                    if numel(this.rec_list) == 0
                        clear rec_list;
                        rec_list(s,:) = this.rec;
                        this.rec_list = rec_list;
                    else
                        this.rec_list(s,:) = this.rec;
                    end
                end
                if ~isunix, fclose('all'); end
            end
            this.log.newLine;
            this.log.addMarkedMessage(sprintf('Computation done in %.2f seconds', toc(t0)));
            this.log.newLine;
        end
        
        function exec(this, cmd)
            this.cmd.exec(this.rec, cmd);
        end
    end
    
    methods (Static)
        function [time_lim_small, time_lim_large] = getRecTimeSpan(session)
            % return a GPS_Time containing the first and last epoch for a session
            %
            % OUTPUT:
            %   time_lim_small     GPS_Time (first and last) epoch of the smaller interval
            %   time_lim_large     GPS_Time (first and last) epoch of the larger interval
            %
            % SYNTAX:
            %   [time_lim_small, time_lim_large] = Core.getRecTimeSpan(session)
            
            state = Global_Configuration.getCurrentSettings();
            rec_files = state.getRecPath();
            for r = 1 : numel(rec_files)
                fr(r) = File_Rinex(rec_files{r}{session}, 100);
            end
            
            time_lim_small = fr(1).first_epoch;
            tmp_small = fr(1).last_epoch;
            time_lim_large = time_lim_small.getCopy;
            tmp_large = tmp_small.getCopy;
            for r = 2 : numel(fr)
                if time_lim_small < fr(r).first_epoch
                    time_lim_small = fr(r).first_epoch;
                end
                if time_lim_large > fr(r).first_epoch
                    time_lim_large = fr(r).first_epoch;
                end
                
                if tmp_small > fr(r).last_epoch
                    tmp_small = fr(r).last_epoch;
                end
                if tmp_large < fr(r).last_epoch
                    tmp_large = fr(r).last_epoch;
                end
            end
            time_lim_small.append(tmp_small);
            time_lim_large.append(tmp_large);
        end
    end
        
    %% METHODS UTILITIES
    % ==================================================================================================================================================
    methods
        function [state, log, w_bar] = getUtilities(this)
            state = this.state;
            log = this.log;
            w_bar = this.w_bar;
        end
    end

    methods % Public Access (Legacy support)
        
    end

end
