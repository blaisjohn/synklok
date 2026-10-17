using System.Net;
using System.Text.Json.Nodes;
using Synklok.Core;

namespace Synklok.Core.Tests;

/// Captures the outgoing request and returns a canned response.
sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
{
    public HttpRequestMessage? LastRequest { get; private set; }
    public string? LastBody { get; private set; }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        LastRequest = request;
        LastBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(ct);
        return respond(request);
    }
}

public class M1620ClientTests
{
    private static HttpResponseMessage Json(string body, HttpStatusCode code = HttpStatusCode.OK) =>
        new(code) { Content = new StringContent(body) };

    [Fact]
    public async Task GetStatus_posts_the_query_and_parses_the_reply()
    {
        var handler = new StubHandler(_ => Json("""
            {"clock":{"sampling_rate":48000,"sources":{"madi_coaxial":{"rate":96000,"sync":true}}}}
            """));
        using var client = new M1620Client("172.20.0.1", handler);

        var status = await client.GetStatusAsync();

        Assert.Equal(HttpMethod.Post, handler.LastRequest!.Method);
        Assert.Equal("http://172.20.0.1/api/v2/self", handler.LastRequest.RequestUri!.ToString());
        Assert.Equal("application/json", handler.LastRequest.Content!.Headers.ContentType!.MediaType);
        var sent = JsonNode.Parse(handler.LastBody!)!;
        Assert.True(sent["clock"]!.AsObject().ContainsKey("sampling_rate"));
        Assert.Null(sent["clock"]!["sampling_rate"]);
        Assert.True(sent["clock"]!["sources"]!["madi_coaxial"]!.AsObject().ContainsKey("sync"));
        Assert.Equal(new DeviceStatus(48000, 96000, true), status);
    }

    [Fact]
    public async Task SetRate_sends_only_the_sampling_rate()
    {
        var handler = new StubHandler(_ => Json("{}"));
        using var client = new M1620Client("10.0.0.5", handler);

        await client.SetRateAsync(96000);

        Assert.Equal("http://10.0.0.5/api/v2/self", handler.LastRequest!.RequestUri!.ToString());
        Assert.Equal("""{"clock":{"sampling_rate":96000}}""", handler.LastBody);
    }

    [Fact]
    public async Task Missing_fields_become_null_rather_than_failing()
    {
        var handler = new StubHandler(_ => Json("""{"clock":{"sampling_rate":44100}}"""));
        using var client = new M1620Client(handler: handler);

        var status = await client.GetStatusAsync();

        Assert.Equal(new DeviceStatus(44100, null, null), status);
    }

    [Fact]
    public async Task Error_status_codes_are_reported_as_unexpected_response()
    {
        var handler = new StubHandler(_ => Json("nope", HttpStatusCode.InternalServerError));
        using var client = new M1620Client(handler: handler);

        var ex = await Assert.ThrowsAsync<M1620Exception>(() => client.GetStatusAsync());
        Assert.Equal("Unexpected response from device", ex.Message);
    }

    [Fact]
    public async Task Garbage_bodies_are_reported_as_unexpected_response()
    {
        var handler = new StubHandler(_ => Json("<html>not json</html>"));
        using var client = new M1620Client(handler: handler);

        await Assert.ThrowsAsync<M1620Exception>(() => client.GetStatusAsync());
    }

    [Fact]
    public async Task Network_failures_are_reported_as_device_errors()
    {
        var handler = new StubHandler(_ => throw new HttpRequestException("No route to host"));
        using var client = new M1620Client(handler: handler);

        var ex = await Assert.ThrowsAsync<M1620Exception>(() => client.GetStatusAsync());
        Assert.Equal("No route to host", ex.Message);
    }
}
