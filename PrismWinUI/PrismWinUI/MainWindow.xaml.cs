using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using PrismAgent;
using System.Collections.ObjectModel;

namespace PrismWinUI;

public sealed partial class MainWindow : Window
{
    private ChatAgent _agent = null!;
    private AppSettings _settings = null!;

    public ObservableCollection<ConvItem> Convs { get; } = new();
    public ObservableCollection<MsgItem> Msgs { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        var dataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Prism");
        _agent = new ChatAgent(dataPath);
        _settings = new AppSettings(); // Load from disk
        if (_agent.Conversations.Count == 0) _agent.CreateConversation();
        RefreshConversations();
    }

    private void RefreshConversations()
    {
        Convs.Clear();
        foreach (var c in _agent.Conversations)
            Convs.Add(new ConvItem { Id = c.Id, Title = c.Title });
        ConversationList.ItemsSource = Convs;
    }

    private void NewConversation_Click(object sender, RoutedEventArgs e) { _agent.CreateConversation(); RefreshConversations(); }

    private void Conversation_Selected(object sender, SelectionChangedEventArgs e)
    {
        if (e.AddedItems.FirstOrDefault() is ConvItem ci)
        {
            _agent.SelectedConversationID = ci.Id;
            RefreshMessages();
        }
    }

    private void RefreshMessages()
    {
        Msgs.Clear();
        var conv = _agent.CurrentConv;
        if (conv == null) return;
        foreach (var m in conv.Messages)
            Msgs.Add(new MsgItem { Sender = m.Role == "user" ? "You" : "Prism", Content = m.Content, IsUser = m.Role == "user" });
        MessageList.ItemsSource = Msgs;
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        var text = InputBox.Text.Trim();
        if (string.IsNullOrEmpty(text) || _agent.IsSending) return;
        InputBox.Text = "";
        Msgs.Add(new MsgItem { Sender = "You", Content = text, IsUser = true });
        var aiMsg = new MsgItem { Sender = "Prism", Content = "", IsUser = false };
        Msgs.Add(aiMsg);

        SendBtn.IsEnabled = false;
        await _agent.SendAsync(text, _settings, (type, token) =>
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                if (type == "content") aiMsg.Content += token;
                MessageScroll.ChangeView(null, MessageScroll.ScrollableHeight, null);
            });
        });
        SendBtn.IsEnabled = true;
        RefreshConversations();
    }

    private void InputBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter) { e.Handled = true; Send_Click(sender, e); }
    }
}

public class ConvItem { public string Id { get; set; } = ""; public string Title { get; set; } = ""; }
public class MsgItem { public string Sender { get; set; } = ""; public string Content { get; set; } = ""; public bool IsUser { get; set; } }
