export namespace main {
	
	export class AudioDevice {
	    name: string;
	    isDefault: boolean;
	
	    static createFrom(source: any = {}) {
	        return new AudioDevice(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.isDefault = source["isDefault"];
	    }
	}
	export class TTSResponse {
	    success: boolean;
	    message: string;
	    error?: string;
	
	    static createFrom(source: any = {}) {
	        return new TTSResponse(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.success = source["success"];
	        this.message = source["message"];
	        this.error = source["error"];
	    }
	}
	export class WSConfig {
	    voice: string;
	    language: string;
	    mic_device: string;
	    speaker_device: string;
	    play_to_speaker: boolean;
	
	    static createFrom(source: any = {}) {
	        return new WSConfig(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.voice = source["voice"];
	        this.language = source["language"];
	        this.mic_device = source["mic_device"];
	        this.speaker_device = source["speaker_device"];
	        this.play_to_speaker = source["play_to_speaker"];
	    }
	}

}

