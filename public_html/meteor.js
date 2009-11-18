/*
stream: xhrinteractive, iframe, serversent
longpoll
smartpoll
simplepoll
*/

Meteor = {

	callbacks: {
		process: function() {},
		reset: function() {},
		eof: function() {},
		statuschanged: function() {},
		changemode: function() {}
	},
	channelcount: 0,
	channels: {},
	debugmode: false,
	frameref: null,
	host: null,
	hostid: null,
	maxpollfreq: 60000,
	minpollfreq: 2000,
	mode: "stream",
	pingtimeout: 20000,
	pingtimer: null,
	pollfreq: 3000,
	port: 80,
	pollaborted: false,
	pollhost: null,
	pollnum: 0,
	polltimeout: 30000,
	polltimer: null,
	recvtimes: [],
	lastrequest: null,
	status: 0,
	updatepollfreqtimer: null,

	isSupportedBrowser: function() {
		var v;
		if (v = navigator.userAgent.match(/compatible\; MSIE\ ([0-9\.]+)\;/i)) {
			if (parseFloat(v[1]) <= 5.5) return false;
		} else if (v = navigator.userAgent.match(/Gecko\/([0-9]+)/i)) {
			if (parseInt(v[1]) <= 20051015) return false;
		} else if (v = navigator.userAgent.match(/WebKit\/([0-9\.]+)/i)) {
			if (parseFloat(v[1]) < 400) return false;
		}
		return true;
	},

	register: function(ifr) {
		ifr.p = Meteor.process;
		ifr.r = Meteor.reset;
		ifr.eof = Meteor.eof;
		ifr.ch = Meteor.channelInfo;
		clearTimeout(Meteor.frameloadtimer);
		Meteor.setstatus(4);
		Meteor.log("Frame registered");
	},

	joinChannel: function(channelname, backtrack) {
		if (!channelname.length) throw('No channel specified');
		if (typeof(Meteor.channels[channelname]) != "undefined") throw "Cannot join channel "+channelname+": already subscribed";
		Meteor.channels[channelname] = {backtrack:backtrack};
		Meteor.log("Joined channel "+channelname);
		Meteor.channelcount++;
		if (Meteor.status != 0 && Meteor.status != 6) Meteor.connect();
	},

	leaveChannel: function(channelname) {
		if (!channelname.length) throw('No channel specified');
		if (typeof(Meteor.channels[channelname]) == "undefined") throw "Cannot leave channel "+channelname+": not subscribed";
		delete Meteor.channels[channelname];
		Meteor.log("Left channel "+channelname);
		Meteor.channelcount--;
		if (Meteor.channelcount && Meteor.status != 0 && Meteor.status != 6) Meteor.connect();
		else Meteor.disconnect();
	},

	connect: function() {
		if (!Meteor.host) throw "Meteor host not specified";
		if (isNaN(Meteor.port)) throw "Meteor port not specified";
		if (!Meteor.channelcount) throw "No channels specified";
		if (Meteor.status) Meteor.disconnect();
		Meteor.log("Connecting");
		Meteor.setstatus(1);
		if (!Meteor.hostid) Meteor.hostid = Meteor.time()+""+Math.floor(Math.random()*1000000)
		document.domain = Meteor.extract_xss_domain(document.domain);
		if (Meteor.mode=="stream") Meteor.mode = Meteor.selectStreamTransport();
		Meteor.log("Selected "+Meteor.mode+" transport");
		if (Meteor.mode=="xhrinteractive" || Meteor.mode=="iframe" || Meteor.mode=="serversent") {
			if (Meteor.mode == "iframe") {
				Meteor.loadFrame(Meteor.getSubsUrl());
			} else {
				Meteor.loadFrame("http://"+Meteor.host+((Meteor.port==80)?"":":"+Meteor.port)+"/stream.html");
			}
			clearTimeout(Meteor.pingtimer);
			Meteor.pingtimer = setTimeout(Meteor.pollmode, Meteor.pingtimeout);

		} else {
			Meteor.recvtimes[0] = Meteor.time();
			if (Meteor.updatepollfreqtimer) clearTimeout(Meteor.updatepollfreqtimer);
			if (Meteor.mode=='smartpoll') Meteor.updatepollfreqtimer = setInterval(Meteor.updatepollfreq, 10000);
			if (Meteor.mode=='longpoll') Meteor.pollfreq = Meteor.minpollfreq;
			Meteor.poll();
		}
	},

	disconnect: function() {
		if (Meteor.status) {
			if (Meteor.status != 6) Meteor.setstatus(0);
			Meteor.clearpoll();
			clearTimeout(Meteor.pingtimer);
			clearTimeout(Meteor.updatepollfreqtimer);
			clearTimeout(Meteor.frameloadtimer);
			if (typeof CollectGarbage == 'function') CollectGarbage();
			Meteor.log("Disconnected");
			try { Meteor.frameref.parentNode.removeChild(Meteor.frameref); delete Meteor.frameref; return true; } catch(e) { }
			try { Meteor.frameref.open(); Meteor.frameref.close(); return true; } catch(e) {}			
		}
	},
	
	selectStreamTransport: function() {
		try {
			var test = ActiveXObject;
			return "iframe";
		} catch (e) {}
		if ((typeof window.addEventStream) == "function") return "iframe";
		return "xhrinteractive";
	},

	getSubsUrl: function() {
		var host = ((Meteor.mode=='simplepoll' || Meteor.mode=='smartpoll' || Meteor.mode=='longpoll') && Meteor.pollhost) ? Meteor.pollhost : Meteor.host;
		var surl = "http://" + host + ((Meteor.port==80)?"":":"+Meteor.port) + "/push/" + Meteor.hostid + "/" + Meteor.mode;
		for (var c in Meteor.channels) {
			surl += "/"+c;
			if (typeof Meteor.channels[c].lastmsgreceived != 'undefined') {
				surl += ".r"+(Meteor.channels[c].lastmsgreceived+1);
			} else if (Meteor.channels[c].backtrack > 0) {
				surl += ".b"+Meteor.channels[c].backtrack;
			} else if (Meteor.channels[c].backtrack != undefined) {
				surl += ".h";
			}
		}
		surl += "?nc="+Meteor.time();
		return surl;
	},

	loadFrame: function(url) {
		try {
			if (!Meteor.frameref) {
				var transferDoc = new ActiveXObject("htmlfile");
				Meteor.frameref = transferDoc;
			}
			Meteor.frameref.open();
			Meteor.frameref.write("<html><script>");
			Meteor.frameref.write("document.domain=\""+(document.domain)+"\";");
			Meteor.frameref.write("</"+"script></html>");
			Meteor.frameref.parentWindow.Meteor = Meteor;
			Meteor.frameref.close();
			var ifrDiv = Meteor.frameref.createElement("div");
			Meteor.frameref.appendChild(ifrDiv);
			ifrDiv.innerHTML = "<iframe src=\""+url+"\"></iframe>";
		} catch (e) {
			if (!Meteor.frameref) {
				var ifr = document.createElement("IFRAME");
				ifr.style.width = "10px";
				ifr.style.height = "10px";
				ifr.style.border = "none";
				ifr.style.position = "absolute";
				ifr.style.top = "-10px";
				ifr.style.marginTop = "-10px";
				ifr.style.zIndex = "-20";
				ifr.Meteor = Meteor;
				document.body.appendChild(ifr);
				Meteor.frameref = ifr;
			}
			Meteor.frameref.setAttribute("src", url);
		}
		Meteor.log("Loading URL '"+url+"' into frame...");
		Meteor.frameloadtimer = setTimeout(Meteor.frameloadtimeout, 5000);
	},

	pollmode: function() {
		Meteor.log("Ping timeout");
		if (Meteor.mode != "smartpoll") {
			Meteor.mode="smartpoll";
			Meteor.callbacks["changemode"]("poll");
			clearTimeout(Meteor.pingtimer);
			Meteor.lastpingtime = false;
		}
		Meteor.connect();
	},

	process: function(id, channel, data) {
		if (id == -1) {
			Meteor.log("Ping");
			Meteor.ping();
		} else if (typeof(Meteor.channels[channel]) != "undefined") {
			Meteor.log("Message "+id+" received on channel "+channel+" (last id on channel: "+Meteor.channels[channel].lastmsgreceived+")\n"+data);
			Meteor.callbacks["process"](data);
			Meteor.channels[channel].lastmsgreceived = id;
			if (Meteor.mode=="smartpoll") {
				Meteor.recvtimes[Meteor.recvtimes.length] = Meteor.time();
				while (Meteor.recvtimes.length > 5) Meteor.recvtimes.shift();
			}
		}
		Meteor.setstatus(5);
	},

	ping: function() {
		if (Meteor.pingtimer) {
			clearTimeout(Meteor.pingtimer);
			Meteor.pingtimer = setTimeout(Meteor.pollmode, Meteor.pingtimeout);
			Meteor.lastpingtime = Meteor.time();
		}
		Meteor.setstatus(5);
	},

	reset: function() {
		if (Meteor.status != 6 && Meteor.status != 0) {
			Meteor.log("Stream reset");
			Meteor.ping();
			Meteor.callbacks["reset"]();
			var x = Meteor.pollfreq - (Meteor.time()-Meteor.lastrequest);
			if (x < 10) x = 10;
			setTimeout(Meteor.connect, x);
		}
	},

	eof: function() {
		Meteor.log("Received end of stream, will not reconnect");
		Meteor.callbacks["eof"]();
		Meteor.setstatus(6);
		Meteor.disconnect();
	},

	channelInfo: function(channel, id) {
		Meteor.channels[channel].lastmsgreceived = id;
		Meteor.log("Received channel info for channel "+channel+": resume from "+id);
	},

	updatepollfreq: function() {
		var avg = 0;
		for (var i=1; i<Meteor.recvtimes.length; i++) {
			avg += (Meteor.recvtimes[i]-Meteor.recvtimes[i-1]);
		}
		avg += (Meteor.time()-Meteor.recvtimes[Meteor.recvtimes.length-1]);
		avg /= Meteor.recvtimes.length;
		var target = avg/2;
		if (target < Meteor.pollfreq && Meteor.pollfreq > Meteor.minpollfreq) Meteor.pollfreq = Math.ceil(Meteor.pollfreq*0.9);
		if (target > Meteor.pollfreq && Meteor.pollfreq < Meteor.maxpollfreq) Meteor.pollfreq = Math.floor(Meteor.pollfreq*1.05);
	},

	registerEventCallback: function(evt, funcRef) {
		Function.prototype.andThen=function(g) {
			var f=this;
			var a=Meteor.arguments
			return function(args) {
				f(a);g(args);
			}
		};
		if (typeof Meteor.callbacks[evt] == "function") {
			Meteor.callbacks[evt] = (Meteor.callbacks[evt]).andThen(funcRef);
		} else {
			Meteor.callbacks[evt] = funcRef;
		}
	},

	frameloadtimeout: function() {
		Meteor.log("Frame load timeout");
		if (Meteor.frameloadtimer) clearTimeout(Meteor.frameloadtimer);
		Meteor.setstatus(3);
		Meteor.pollmode();
	},

	extract_xss_domain: function(old_domain) {
		if (old_domain.match(/^(\d{1,3}\.){3}\d{1,3}$/)) return old_domain;
		domain_pieces = old_domain.split('.');
		return domain_pieces.slice(-2, domain_pieces.length).join(".");
	},

	setstatus: function(newstatus) {
		// Statuses:	0 = Uninitialised,
		//				1 = Loading stream,
		//				2 = Loading controller frame,
		//				3 = Controller frame timeout, retrying.
		//				4 = Controller frame loaded and ready
		//				5 = Receiving data
		//				6 = End of stream, will not reconnect

		if (Meteor.status != newstatus) {
			Meteor.status = newstatus;
			Meteor.callbacks["statuschanged"](newstatus);
		}
	},

	log: function(logstr) {
		if (Meteor.debugmode) {
			if (window.console) {
				window.console.log(logstr);
			} else if (document.getElementById("meteorlogoutput")) {
				document.getElementById("meteorlogoutput").innerHTML += logstr+"<br/>";
			}
		}
	},

	poll: function() {
		Meteor.pollaborted = 0;
		try {
			clearTimeout(Meteor.polltimer);
		} catch (e) {};
		Meteor.lastrequest = Meteor.time();
		if (Meteor.polltimeout) Meteor.polltimer = setTimeout(Meteor.clearpoll, Meteor.polltimeout);
		var scripttag = document.createElement("SCRIPT");
		scripttag.type = "text/javascript";
		scripttag.src = Meteor.getSubsUrl();
		scripttag.id = "meteorpoll"+(++Meteor.pollnum);
		scripttag.className = "meteorpoll";
		document.getElementsByTagName("HEAD")[0].appendChild(scripttag);
	},

	clearpoll: function() {
		if (document.getElementById('meteorpoll'+Meteor.pollnum)) {
			var s = document.getElementById('meteorpoll'+Meteor.pollnum);
			s.parentNode.removeChild(s);
		}
		if (Meteor.status == 5) {
			var x = parent.Meteor.pollfreq - (Meteor.time()-Meteor.lastrequest);
			if (x < 10) x = 10;
			setTimeout(Meteor.poll, x);
		}
	},

	time: function() {
		var now = new Date();
		return now.getTime();
	}
}

var oldonunload = window.onunload;
if (typeof window.onunload != 'function') {
	window.onunload = Meteor.disconnect;
} else {
	window.onunload = function() {
		if (oldonunload) oldonunload();
		Meteor.disconnect();
	}
}