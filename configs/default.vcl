vcl 4.1;

backend default {
    .host = "172.31.17.33";
    .port = "80";
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
