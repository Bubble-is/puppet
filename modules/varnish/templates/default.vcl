# This is the VCL file for Varnish, adjusted for Miraheze's needs.
# It was mostly written by Southparkfan, with some stuff by Wikimedia.

# Credits go to Southparkfan and the contributors of Wikimedia's Varnish configuration.
# See their Puppet repo (https://github.com/wikimedia/operations-puppet)
# for the LICENSE.

# If you have any questions about the Varnish setup,
# please contact Southparkfan <southparkfan [at] miraheze [dot] org>.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import directors;
import std;

probe mwhealth {
	.request = "GET /wiki/Main_Page HTTP/1.1"
		"Host: login.miraheze.org"
		"User-Agent: Varnish healthcheck"
		"Connection: close";
	# Check each 10s
	.interval = 10s;
	# May not take longer than 8s to load. Ideally this should be lowered, but sometimes latency to the NL servers could suck.
	.timeout = 20s;
	# At least 4 out of 5 checks must be successful
	# to mark the backend as healthy
	.window = 5;
	.threshold = 4;
	.expected_response = 200;
}

backend misc2 {
    .host = "127.0.0.1";
    .port = "8201";
} 

backend lizardfs6 {
    .host = "127.0.0.1";
    .port = "8203";
    .probe = mwhealth;
}

backend mw1 {
	.host = "127.0.0.1";
	.port = "8080";
	.probe = mwhealth;
}

backend mw2 {
	.host = "127.0.0.1";
	.port = "8081";
	.probe = mwhealth;
}

backend mw3 {
	.host = "127.0.0.1";
	.port = "8082";
	.probe = mwhealth;
}

backend test1 {
	.host = "127.0.0.1";
	.port = "8083";
}

# test mediawiki backend with out health check
# to be used only by our miraheze debug plugin

backend mw1_test {
	.host = "127.0.0.1";
	.port = "8080";
}

backend mw2_test {
	.host = "127.0.0.1";
	.port = "8081";
}

backend mw3_test {
	.host = "127.0.0.1";
	.port = "8082";
}

backend lizardfs6_no_check {
    .host = "127.0.0.1";
    .port = "8203";
}

# end test backend


sub vcl_init {
	new mediawiki = directors.round_robin();
	mediawiki.add_backend(lizardfs6);
	mediawiki.add_backend(mw1);
	mediawiki.add_backend(mw2);
	mediawiki.add_backend(mw3);
}


acl purge {
	"localhost";
	"54.36.165.161"; # lizardfs6
	"185.52.1.75"; # mw1
	"2a00:d880:6:786::2"; # mw1
	"185.52.2.113"; # mw2
	"2a00:d880:5:799::2"; # mw2
	"81.4.121.113"; # mw3
	"2a00:d880:5:b45::2"; # mw3
	"185.52.2.243"; # test1
	"81.4.127.174"; # misc2
	"185.52.3.121"; # misc4
	"2a00:d880:5:7c6::2"; # misc4
}

sub mw_stash_cookie {
	if (req.restarts == 0) {
		unset req.http.Cookie;
	}
}

sub mw_evaluate_cookie {
	if (req.http.Cookie ~ "([sS]ession|Token)=" 
		&& req.url !~ "^/w/load\.php"
		# FIXME: Can this just be req.http.Host !~ "static.miraheze.org"?
                && req.url !~ "^/.*wiki/(thumb/)?[0-9a-f]/[0-9a-f]{1,2}/.*\.(png|jpe?g|svg)$"
                && req.url !~ "^/w/resources/assets/.*\.png$"
		&& req.url !~ "^/(wiki/?)?$"
	) {
		# To prevent issues, we do not want vcl_backend_fetch to add ?useformat=mobile
		# when the user directly contacts the backend. The backend will directly listen to the cookies
		# the user sets anyway, the hack in vcl_backend_fetch is only for users that are not logged in.
		set req.http.X-Use-Mobile = "0";
		return (pass);
	} else {
		call mw_stash_cookie;
	}
}

sub mw_identify_device {
	# Used in vcl_backend_fetch and vcl_hash
	set req.http.X-Device = "desktop";
	
	# If the User-Agent matches the regex (this is the official regex used in MobileFrontend for automatic device detection), 
	# and the cookie does NOT explicitly state the user does not want the mobile version, we
	# set X-Device to phone-tablet. This will make vcl_backend_fetch add ?useformat=mobile to the URL sent to the backend.
	if (req.http.User-Agent ~ "(?i)(mobi|240x240|240x320|320x320|alcatel|android|audiovox|bada|benq|blackberry|cdm-|compal-|docomo|ericsson|hiptop|htc[-_]|huawei|ipod|kddi-|kindle|meego|midp|mitsu|mmp\/|mot-|motor|ngm_|nintendo|opera.m|palm|panasonic|philips|phone|playstation|portalmmm|sagem-|samsung|sanyo|sec-|semc-browser|sendo|sharp|silk|softbank|symbian|teleca|up.browser|vodafone|webos)" && req.http.Cookie !~ "(stopMobileRedirect=true|mf_useformat=desktop)") {
		set req.http.X-Device = "phone-tablet";

		# In vcl_fetch we'll decide in which situations we should actually do something with this.
		set req.http.X-Use-Mobile = "1";
	}

	if (req.http.host ~ "^([a-zA-Z0-9].+)\.m\.miraheze\.org") {
		set req.http.X-Subdomain = "M";
	} else if (req.http.host ~ "^m\.([a-zA-Z0-9\-\.].+)") {
		set req.http.X-Subdomain = "M";
	} else if (req.http.host ~ "^([a-zA-Z0-9\-\.]+)\.m\.([a-zA-Z0-9\-\.].+)") {
		set req.http.X-Subdomain = "M";
	}
}

sub mw_url_rewrite {
        if (req.http.Host == "meta.miraheze.org"
                && req.url ~ "^/Stewards'_noticeboard"
        ) {
                return (synth(752, "/wiki/Stewards'_noticeboard"));
        } else if (req.http.Host == "meta.m.miraheze.org"
                && req.url ~ "^/Stewards'_noticeboard"
        ) {
                return (synth(752, "/wiki/Stewards'_noticeboard"));
	}
        
	if (req.http.Host == "meta.miraheze.org"
		&& req.url ~ "^/Requests_for_adoption"
	) {
		return (synth(752, "/wiki/Requests_for_adoption"));
	} else if (req.http.Host == "meta.m.miraheze.org"
		&& req.url ~ "^/Requests_for_adoption"
	) {
		return (synth(752, "/wiki/Requests_for_adoption"));
	}
}

sub vcl_synth {
        if (resp.status == 752) {
                set resp.http.Location = resp.reason;
                set resp.status = 302;
                return (deliver);
        }
}

sub recv_purge {
	if (req.method == "PURGE") {
		if (!client.ip ~ purge) {
			return (synth(405, "Denied."));
		} else {
			return (purge);
		}
	}
}

sub mw_vcl_recv {
	call mw_identify_device;
	call mw_url_rewrite;

	# Redirects <url>/sitemap to static.miraheze.org/sitemap/
	if (req.url ~ "^/sitemap" && req.http.Host != "static.miraheze.org") {
		set req.url = "/sitemaps/" + req.http.Host + req.url;
		set req.http.Host = "static.miraheze.org";
	}

	if (req.http.X-Miraheze-Debug == "mw1.miraheze.org" || req.url ~ "^/\.well-known") {
		set req.backend_hint = mw1_test;
		return (pass);
	} else if (req.http.X-Miraheze-Debug == "mw2.miraheze.org") {
		set req.backend_hint = mw2_test;
		return (pass);
	} else if (req.http.X-Miraheze-Debug == "mw3.miraheze.org") {
		set req.backend_hint = mw3_test;
		return (pass);
	} else if (req.http.X-Miraheze-Debug == "test1.miraheze.org") {
		set req.backend_hint = test1;
		return (pass);
	} else if (req.http.X-Miraheze-Debug == "lizardfs6.miraheze.org") {
		set req.backend_hint = lizardfs6_no_check;
		return (pass);
	} else {
		set req.backend_hint = mediawiki.backend();
	}

	# We never want to cache non-GET/HEAD requests.
	if (req.method != "GET" && req.method != "HEAD") {
		# Zero reason to append ?useformat=true here.
		set req.http.X-Use-Mobile = "0";
		return (pass);
	}

	if (req.http.If-Modified-Since && req.http.Cookie ~ "LoggedOut") {
		unset req.http.If-Modified-Since;
	}

	# Don't cache dumps, and such
	if (req.http.Host == "static.miraheze.org" && req.url !~ "^/.*wiki") {
		return (pass);
	}

	if (req.http.Host == "static-temp.miraheze.org" && req.url !~ "^/.*wiki") {
		return (pass);
	}

	# We can rewrite those to one domain name to increase cache hits!
	if (req.url ~ "^/w/resources") {
		set req.http.Host = "meta.miraheze.org";
	}
 
	if (req.http.Authorization ~ "OAuth") {
		return (pass);
	}

	if (req.url ~ "^/healthcheck$") {
		set req.http.Host = "login.miraheze.org";
		set req.url = "/wiki/Main_Page";
		return (pass);
	}
	
	# Temporary solution to fix CookieWarning issue with ElectronPDF

	if (req.http.X-Real-IP == "185.52.1.71") {
		return (pass);
	}

	call mw_evaluate_cookie;
}

sub vcl_recv {
	call recv_purge;

	unset req.http.Proxy; # https://httpoxy.org/; CVE-2016-5385

	# Normalize Accept-Encoding for better cache hit ratio
	if (req.http.Accept-Encoding) {
		if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
			# No point in compressing these
			unset req.http.Accept-Encoding;
		} elsif (req.http.Accept-Encoding ~ "gzip") {
			set req.http.Accept-Encoding = "gzip";
		} elsif (req.http.Accept-Encoding ~ "deflate") {
			set req.http.Accept-Encoding = "deflate";
		} else {
			# We don't understand this
			unset req.http.Accept-Encoding;
		}
	}

	if (req.http.Host == "matomo.miraheze.org") {
		set req.backend_hint = misc2;

		# Yes, we only care about this file
		if (req.url ~ "^/piwik.js" || req.url ~ "^/matomo.js") {
			return (hash);
		} else {
			return (pass);
		}
	}

	# MediaWiki specific
	call mw_vcl_recv;

	return (hash);
}

sub vcl_hash {
	# FIXME: try if we can make this ^/wiki/ only?
	if (req.url ~ "^/wiki/" || req.url ~ "^/w/load.php") {
		hash_data(req.http.X-Device);
	}
}

sub vcl_backend_fetch {
	if ((bereq.url ~ "^/wiki/[^$]" || bereq.url ~ "^/w/index.php\?title=[^$]") && bereq.http.X-Device == "phone-tablet" && bereq.http.X-Use-Mobile == "1") {
		if (bereq.url ~ "\?") {
		        set bereq.url = bereq.url + "&useformat=mobile";
		} else {
		        set bereq.url = bereq.url + "?useformat=mobile";
		}
	}
}

sub vcl_backend_response {
	if (beresp.ttl <= 0s) {
		set beresp.ttl = 1800s;
		set beresp.uncacheable = true;
	}

	if (beresp.status >= 400) {
		set beresp.uncacheable = true;
	}

	# Cache 301 redirects for 12h (/, /wiki, /wiki/ redirects only)
	if (beresp.status == 301 && bereq.url ~ "^/?(wiki/?)?$" && !beresp.http.Cache-Control ~ "no-cache") {
		set beresp.ttl = 43200s;
	}

	return (deliver);
}

sub vcl_deliver {
	if (req.url ~ "^/wiki/" || req.url ~ "^/w/index\.php") {
		if (req.url !~ "^/wiki/Special\:Banner") {
			set resp.http.Cache-Control = "private, s-maxage=0, maxage=0, must-revalidate";
		}
	}
set resp.http.Alt-Svc = 'quic="<%= scope.lookupvar('::hostname') %>:443", v="22,25,27", ma=86400';
	if (obj.hits > 0) {
		set resp.http.X-Cache = "<%= scope.lookupvar('::hostname') %> hit/" + obj.hits + "";
	} else {
		set resp.http.X-Cache = "<%= scope.lookupvar('::hostname') %> miss/0";
	}

	set resp.http.Content-Security-Policy = "default-src 'self' blob: data: <%- @csp_whitelist.each_pair do |config, value| -%> <%= value %> <%- end -%> 'unsafe-inline' 'unsafe-eval'; frame-ancestors 'self' <%- @frame_whitelist.each_pair do |config, value| -%> <%= value %> <%- end -%>";
}

sub vcl_backend_error {
	set beresp.http.Content-Type = "text/html; charset=utf-8";

	synthetic( {"<!DOCTYPE html>
	<html lang="en">
		<head>
			<meta charset="utf-8">
			<meta name="viewport" content="width=device-width, initial-scale=1.0">
			<meta name="description" content="Backend Fetch Failed">
			<title>"} + beresp.status + " " + beresp.reason + {"</title>
			<!-- Bootstrap core CSS -->
			<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css">
			<style>
				/* Error Page Inline Styles */
				body {
					padding-top: 20px;
				}
				/* Layout */
				.jumbotron {
					font-size: 21px;
					font-weight: 200;
					line-height: 2.1428571435;
					color: inherit;
					padding: 10px 0px;
				}
				/* Everything but the jumbotron gets side spacing for mobile-first views */
				.masthead, .body-content {
					padding-left: 15px;
					padding-right: 15px;
				}
				/* Main marketing message and sign up button */
				.jumbotron {
					text-align: center;
					background-color: transparent;
				}
				.jumbotron .btn {
					font-size: 21px;
					padding: 14px 24px;
				}
				/* Colors */
				.green {color:#5cb85c;}
				.orange {color:#f0ad4e;}
				.red {color:#d9534f;}
			</style>
			<script>
				function loadDomain() {
					var display = document.getElementById("display-domain");
					display.innerHTML = document.domain;
				}
			</script>
		</head>
		<div class="container">
			<!-- Jumbotron -->
			<div class="jumbotron">
				<h1><img src="https://upload.wikimedia.org/wikipedia/commons/b/b7/Miraheze-Logo.svg" alt="Miraheze Logo"> "} + beresp.status + " " + beresp.reason + {"</h1>
				<p class="lead">Our servers are having issues at the moment.</p>
				<a href="javascript:document.location.reload(true);" class="btn btn-default btn-lg text-center"><span class="green">Try This Page Again</span></a>
			</div>
		</div>
		<div class="container">
			<div class="body-content">
				<div class="row">
					<div class="col-md-6">
						<h2>What can I do?</h2>
						<p class="lead">If you're a wiki visitor or owner</p>
						<p>Try again in a few minutes. If the problem persists, please report this on <a href="https://phabricator.miraheze.org">phabricator.</a> We apologize for the inconvenience. Our sysadmins should be attempting to solve the issue ASAP!</p>
					</div>
					<div class="col-md-6">
						<a class="twitter-timeline" data-width="500" data-height="350" text-align: center href="https://twitter.com/miraheze?ref_src=twsrc%5Etfw">Tweets by miraheze</a> <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
					</div>
				</div>
			</div>
		</div>

                <div class="footer">
			<div class="text-center">
				<p class="lead">When reporting this, please be sure to provide the information below.</p>

				Error "} + beresp.status + " " + beresp.reason + {", forwarded for "} + bereq.http.X-Forwarded-For + {" <br />
				(Varnish XID "} + bereq.xid + {") via "} + server.identity + {" at "} + now + {".
				<br /><br />


			</div>
		</div>
	</html>
	"} );

	return (deliver);
}
