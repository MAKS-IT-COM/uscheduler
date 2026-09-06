using System.Globalization;
using Avalonia.Data.Converters;
using Avalonia.Media;


namespace MaksIT.UScheduler.UI;

public sealed class NamedColorBrushConverter : IValueConverter {
  public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) {
    var name = value as string;
    var hex = name switch {
      "Green" => "#32cd32",
      "Red" => "#e74c3c",
      "Orange" => "#f39c12",
      _ => "#9aa0a6"
    };

    return new SolidColorBrush(Color.Parse(hex));
  }

  public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
    throw new NotSupportedException();
}
